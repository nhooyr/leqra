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
    $unused, $a,    $ap, $assets, $b,   $badge, $c,  $checks, $errors, $f,
    $h,      $html, $i,  $js,     $out, $p,     $pw, $r,      $w,      $web
);

# v4.12 focused browser checks: removed loadout key badge/share return, Giant 8-FFA preset, larger remote/bot power badges.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'tests/results/v4.12-browser' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish412_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish412_browser.pl --output
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
$c = $b->newContext( { viewport => { 'width' => 320, 'height' => 568 }, colorScheme => 'dark' } );
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
wait_js( $p, 'window.__test&&leqra.version===\'4.12.0\'' );
main::check(
    ( value_eq( $p->locator('.loadout-key')->count(), 0 ) ),
    'under-arena fire-key badges are removed entirely'
);
main::check(
    ( value_eq( $p->locator('#bestInline')->innerText(), '' ) ),
    'under-arena offline score placeholder starts empty'
);
$p->locator('#roomPresetsBtn')->click();
$p->locator('#presetSelect')->selectOption( { label => '8-tank Free-for-all' } );
$p->locator('#loadPresetBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    evaluate_js(
        $p,
'__test.localRoom.players.length===8&&__test.currentRules().teamMode===\'ffa\'&&__test.currentRules().mapSize===\'giant\''
    ),
    '8-tank FFA preset uses Giant 16×14'
);
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
evaluate_js( $p, '__test.setPhase(\'playing\')' );
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    ( !truth_value( $p->locator('#copyInGameBtn')->isVisible() ) ),
    'local in-game menu has no Return to room to share online button'
);
main::check( $p->locator('#restartLocalBtn')->isVisible(), 'local Restart match action remains available' );
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$badge = evaluate_js( $p,
'()=>{const t=__test.tanks.find(t=>!t.human);Object.assign(t,{alive:true,power:\'scatter\',powerTime:10,shield:10,shieldCharges:2,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10});const c=document.getElementById(\'arena\').getContext(\'2d\'),old=c.drawImage,calls=[];c.drawImage=function(...a){if(a.length>=5)calls.push([a[1],a[2],a[3],a[4]]);return old.apply(this,a)};try{__test.drawTankPowerBadges(t);}finally{c.drawImage=old}return{calls,kinds:__test.activeTankPowerBadges(t)};}'
);
main::check(
    ( value_eq( scalar( @{ $badge->{'calls'} } ), 5 ) ),
    'all active remote/bot effects still draw power badges'
);
main::check(
    !scalar(
        grep {
            my ( $ignore_0, $ignore_1, $w, $h ) = @{$_};
            !(
                (
                    do {
                        my $boolean_value = ( ( $w >= 26 ) );
                        truth_value($boolean_value)
                          ? ( ( $h >= 26 ) )
                          : $boolean_value;
                    }
                )
            )
        } @{ $badge->{'calls'} }
    ),
    'remote/bot power badges are at least double the old 13-unit size'
);
$p->screenshot( { path => format_value( $out->child('playing-320x568.png') ) } );
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'    => '4.12.0',
            'passed'     => scalar( @{$checks} ),
            'checks'     => $checks,
            'errors'     => $errors,
            'badgeCalls' => $badge->{'calls'}
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
