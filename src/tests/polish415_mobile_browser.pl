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

my ( $a, $ap, $assets, $b, $c, $checks, $errors, $f, $html, $i, $js, $metrics, $out, $p, $pw, $r, $web );

# v4.15 narrow-phone layout smoke checks for Ultra Wide and fixed-height feedback.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'tests/results/v4.15-mobile' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish415_mobile_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish415_mobile_browser.pl --output
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
$c = $b->newContext(
    {
        viewport    => { 'width' => 390, 'height' => 844 },
        colorScheme => 'dark',
        hasTouch    => JSON::PP::true,
        isMobile    => JSON::PP::true
    }
);
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
wait_js( $p, 'window.__test&&leqra.version===\'4.35.0\'' );
evaluate_js( $p, '__test.createLocalRoom()' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
evaluate_js( $p,
'()=>{__test.setLocalRules({...__test.currentRules(),mapSize:\'ultrawide\'});__test.addRoomSeat(\'local\')}'
);
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
evaluate_js( $p,
    '()=>{__test.setPhase(\'playing\');__test.showStartingControls();__test.updateHUD(true);__test.render()}'
);
$metrics = evaluate_js( $p,
'()=>{const body=document.documentElement,wrap=document.querySelector(\'#arenaWrap\').getBoundingClientRect(),under=document.querySelector(\'.underbar\').getBoundingClientRect(),before=under.height;__test.setPilotFeedback(1,\'LASER, RICOCHETS, MAZE-PERIMETER RANGE\',99);__test.updateHUD(true);return{scrollWidth:body.scrollWidth,clientWidth:body.clientWidth,wrapLeft:wrap.left,wrapRight:wrap.right,underBefore:before,underAfter:document.querySelector(\'.underbar\').getBoundingClientRect().height,p1:document.querySelector(\'#pilotLoadout1\').hidden,p2:document.querySelector(\'#pilotLoadout2\').hidden,world:leqra.getState().world};}'
);
main::check(
    ( ( $metrics->{'scrollWidth'} <= ( $metrics->{'clientWidth'} + 1 ) ) ),
    'Ultra Wide mobile page has no horizontal document overflow'
);
main::check(
    (
        do {
            my $boolean_value = ( ( $metrics->{'wrapLeft'} >= (-1) ) );
            truth_value($boolean_value)
              ? ( ( $metrics->{'wrapRight'} <= 391 ) )
              : $boolean_value;
        }
    ),
    'arena container stays inside the 390px viewport'
);
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $metrics->{'world'}->{'cols'}, 24 ) );
            truth_value($boolean_value)
              ? ( value_eq( $metrics->{'world'}->{'rows'}, 14 ) )
              : $boolean_value;
        }
    ),
    'mobile uses the actual 24×14 Ultra Wide world'
);
main::check(
    (
        do {
            my $boolean_value = ( !truth_value( $metrics->{'p1'} ) );
            truth_value($boolean_value)
              ? ( !truth_value( $metrics->{'p2'} ) )
              : $boolean_value;
        }
    ),
    'both local pilot loadouts remain available on narrow mobile'
);
main::check( ( ( abs( ( $metrics->{'underBefore'} - $metrics->{'underAfter'} ) ) < 0.6 ) ),
    'P2 feedback does not grow the mobile status underbar' );
main::check( ( !truth_value($errors) ), ( 'no uncaught mobile browser errors: ' . format_value($errors) ) );
evaluate_js( $p, '__test.render()' );
$p->screenshot(
    {
        path     => format_value( $out->child('v415-mobile.png') ),
        fullPage => JSON::PP::true
    }
);
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version' => '4.35.0',
            'passed'  => scalar( @{$checks} ),
            'checks'  => $checks,
            'errors'  => $errors,
            'metrics' => $metrics
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
