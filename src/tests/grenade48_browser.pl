#!/usr/bin/env perl
package main;
use v5.34;
use strict;
use warnings;
use utf8;
use Encode ();
binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";
use FindBin;
use lib "$FindBin::Bin/lib";
use Leqra::Browser;

my (
    $a,    $ap, $assets, $b,   $c, $checks, $errors, $f,      $forecast,
    $html, $i,  $js,     $out, $p, $pw,     $r,      $ratios, $web
);

# v4.8 focused browser check: long-fuse grenade cruises before late braking.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'test-output/grenade48' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl grenade48_browser.pl --output
';
    if ($help) {
        print 'Usage: perl grenade48_browser.pl --output
';
        exit 0;
    }
    \%args;
};
$r      = path($0)->absolute->parent(2);
$web    = $r->child('web');
$assets = asset_directory($web);
$out    = path( $a->{'output'} );
$out->mkpath;
$html = replace_text(
    replace_re( '<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8 ),
    '</head>',
    (
        ( ( '<style>' . $assets->child('theme.css')->slurp_utf8 ) . $assets->child('style.css')->slurp_utf8 )
        . '</style></head>'
    )
);
$js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1 );
$i  = rindex( $js, '})()' );
$js =
  ( ( substr( $js, 0, $i - 0 ) . '})(window.__location,window.__history);' ) . substr( $js, ( $i + 4 ) ) );
$checks = [];
$errors = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$c = $b->newContext( { viewport => { 'width' => 390, 'height' => 844 }, colorScheme => 'dark' } );
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
$p->setContent($html);
evaluate_js( $p,
'()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={\'leqra.name\':\'ALPHA\',\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}'
);

for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
    $p->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
}
$p->addScriptTag( { content => $js } );
wait_js( $p, 'window.__test&&leqra.version===\'4.8.0\'' );
$ratios = evaluate_js( $p,
'()=>({at5:__test.grenadeDragFactor(10,5),at8:__test.grenadeDragFactor(10,2),at9:__test.grenadeDragFactor(10,1),final:__test.grenadeDragFactor(10,0)})'
);
main::check( ( ( $ratios->{'at5'} > 0.87 ) ), 'grenade retains over 87% speed halfway through fuse' );
main::check( ( ( $ratios->{'at8'} > 0.74 ) ), 'grenade retains over 74% speed with two seconds left' );
main::check(
    ( ( 0.39 < $ratios->{'at9'} ) && ( $ratios->{'at9'} < 0.5 ) ),
    'grenade brakes strongly during final second approach'
);
main::check( ( ( 0.09 < $ratios->{'final'} ) && ( $ratios->{'final'} < 0.12 ) ),
    'grenade finishes fuse near 10% launch speed' );
$forecast = evaluate_js( $p,
'()=>{__test.setWorld({width:10000,height:10000,cols:100,rows:100,walls:[]});const b={kind:\'grenade\',owner:7,x:5000,y:5000,vx:205,vy:0,r:6,life:10,bounces:0};const q=__test.grenadeForecast(b,5);return {speed:Math.hypot(q.vx,q.vy),life:q.life,x:q.x}}'
);
main::check(
    (
        do {
            my $boolean_value = ( ( ( $forecast->{'speed'} / 205 ) > 0.87 ) );
            truth_value($boolean_value)
              ? ( ( abs( ( $forecast->{'life'} - 5 ) ) < 0.02 ) )
              : $boolean_value;
        }
    ),
    'AI grenade forecast uses cruise-phase drag and advances fuse'
);
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'  => '4.8.0',
            'passed'   => scalar( @{$checks} ),
            'checks'   => $checks,
            'errors'   => $errors,
            'ratios'   => $ratios,
            'forecast' => $forecast
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
