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
    $a,      $ap,     $assets,   $avoid, $b,    $c,    $checks,
    $clear,  $errors, $expected, $f,     $html, $i,    $js,
    $manual, $out,    $p,        $pw,    $r,    $spec, $web
);

# v4.9 focused browser checks: grenade-body avoidance, quarter-range Machine gun, version/manual UI.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'test-output/polish49' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish49_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish49_browser.pl --output
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
wait_js( $p, 'window.__test&&leqra.version===\'4.9.0\'' );
$spec = evaluate_js( $p,
'()=>{__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});return __test.projectileSpec(\'rapid\')}'
);
$expected = ( ( 504 + 420 ) / ( 2 * ( 282 * 3 ) ) );
main::check(
    ( ( abs( ( $spec->{'life'} - $expected ) ) < 1e-09 ) ),
    'Machine gun client range is one quarter of maze perimeter'
);
$avoid = evaluate_js( $p,
'()=>{const t=__test.tanks[0];Object.assign(t,{x:100,y:210,angle:0,r:17,difficulty:\'easy\',ghostTime:0});__test.clearBullets();__test.addBullet({id:1,owner:1,kind:\'grenade\',x:158,y:210,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,{angle:0,drive:1},{speed:89,turn:2.8})}'
);
main::check(
    (
        do {
            my $boolean_value = ( defined($avoid) );
            truth_value($boolean_value)
              ? (
                do {
                    my $boolean_value = ( ( abs( $avoid->{'angle'} ) > 0.15 ) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( ( $avoid->{'drive'} <= 0.25 ) );
                }
              )
              : $boolean_value;
        }
    ),
    'bot steers/brakes instead of headbutting grenade body'
);
$clear = evaluate_js( $p,
'()=>{const t=__test.tanks[0];__test.clearBullets();__test.addBullet({id:2,owner:1,kind:\'grenade\',x:180,y:330,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,{angle:0,drive:1},{speed:89,turn:2.8})}'
);
main::check( ( !defined($clear) ), 'bot does not avoid the grenade full explosion radius' );
$p->click('#roomControlsBtn');
main::check( ( contains_value( $p->locator('#controlsDialog')->innerText(), 'leqra v4.9.0' ) ),
    'Controls menu shows game version' );
evaluate_js( $p, 'document.querySelector(\'#controlsDialog\').close()' );
$manual = $p->locator('#manualContent')->innerText();
main::check( ( contains_value( $manual, 'Use Controls menu to change keys.' ) ),
    'Field Manual wording says Controls menu' );
main::check( ( !( contains_value( $manual, 'Use Controls to change keys.' ) ) ),
    'old Field Manual wording removed' );
main::check( ( contains_value( $p->locator('.power-list')->textContent(), 'Quarter-perimeter range.' ) ),
    'Machine gun legend describes quarter-perimeter range' );
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version' => '4.9.0',
            'passed'  => scalar( @{$checks} ),
            'checks'  => $checks,
            'errors'  => $errors
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
