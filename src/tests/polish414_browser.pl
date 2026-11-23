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

my ( $a, $after_state, $ap, $assets, $b,
    $before, $before_state, $c,  $checks, $errors,       $f, $fire_btn, $html, $i, $js,
    $out,    $p,            $pw, $r,      $score_layout, $web );

# v4.14 focused browser checks: F fullscreen, always-on one-line summary scores, round-preserving restart.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'tests/results/v4.14-browser' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish414_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish414_browser.pl --output
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
$c = $b->newContext( { viewport => { 'width' => 1365, 'height' => 950 }, colorScheme => 'dark' } );
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
wait_js( $p, 'window.__test&&leqra.version===\'4.14.0\'' );
main::check(
    (
        do {
            my $boolean_value = $p->locator('.sidebar')->isVisible();
            truth_value($boolean_value)
              ? (
                !(
                    contains_value(
                        (
                            do {
                                my $boolean_value = $p->locator('body')->getAttribute('class');
                                truth_value($boolean_value)
                                  ? $boolean_value
                                  : '';
                            }
                        ),
                        'sidebar-hidden'
                    )
                )
              )
              : $boolean_value;
        }
    ),
    'desktop sidebar is present for scoreboard visibility check'
);
main::check(
    ( value_eq( evaluate_js( $p->locator('#miniScores'), 'e=>getComputedStyle(e).display' ), 'flex' ) ),
    'summary scoreboard stays active with sidebar visible' );
$p->locator('#roomPresetsBtn')->click();
$p->locator('#presetSelect')->selectOption( { label => '8-tank Free-for-all' } );
$p->locator('#loadPresetBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
evaluate_js( $p, '__test.updateHUD(true)' );
$score_layout = evaluate_js( $p->locator('#miniScores'),
'e=>{const r=[...e.children].map(x=>x.getBoundingClientRect());return{count:r.length,top:r.map(x=>Math.round(x.top)),height:e.getBoundingClientRect().height,scrollHeight:e.scrollHeight,clientHeight:e.clientHeight,display:getComputedStyle(e).display}}'
);
main::check( ( value_eq( $score_layout->{'count'}, 8 ) ), 'eight-tank FFA shows all eight summary scores' );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( scalar( @{ unique_values( $score_layout->{'top'} ) } ), 1 ) );
            truth_value($boolean_value)
              ? ( ( $score_layout->{'scrollHeight'} <= ( $score_layout->{'clientHeight'} + 1 ) ) )
              : $boolean_value;
        }
    ),
    'five-plus tank summary scoreboard is forced to one line'
);
$p->keyboard()->press('f');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(160) );
main::check( evaluate_js( $p, '!!document.fullscreenElement' ), 'F enters fullscreen' );
$p->keyboard()->press('f');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(120) );
main::check( ( !truth_value( evaluate_js( $p, '!!document.fullscreenElement' ) ) ), 'F exits fullscreen' );
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$p->locator('#menuControlsBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$fire_btn = $p->locator('[data-bind="0:fire"]');
$before   = $fire_btn->innerText();
$fire_btn->click();
$p->keyboard()->press('f');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    (
        do {
            my $boolean_value =
              ( ( index( lc( $p->locator('#controlsNotice')->innerText() ), 'reserved' ) >= 0 ) );
            truth_value($boolean_value)
              ? ( value_eq( evaluate_js( $p, '__test.bindings[0].fire' ), 'KeyQ' ) )
              : $boolean_value;
        }
    ),
    'F is reserved for fullscreen instead of gameplay binding'
);
$p->locator('[data-close-dialog="controlsDialog"]')->click();
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
evaluate_js( $p,
'()=>{__test.setPhase(\'playing\');__test.finishRound(0);__test.startRound();__test.setPhase(\'playing\');}'
);
$before_state = evaluate_js( $p, 'leqra.getState()' );
main::check(
    ( ( max( @{ $before_state->{'scores'} } ) > 0 ) ),
    'restart preservation test begins with a nonzero match score'
);
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check( ( index( lc( $p->locator('#restartLocalBtn')->innerText() ), 'restart round' ) == 0 ),
    'elimination pause menu labels the action Restart round' );
$p->locator('#restartLocalBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
$after_state = evaluate_js( $p, 'leqra.getState()' );
main::check( ( value_eq( $after_state->{'phase'}, 'countdown' ) ), 'Restart round begins a fresh countdown' );
main::check( ( value_eq( $after_state->{'scores'}, $before_state->{'scores'} ) ),
    'Restart round preserves the current match score' );
main::check( ( value_eq( $after_state->{'round'}, $before_state->{'round'} ) ),
    'Restart round preserves the current round number' );
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$p->screenshot( { path => format_value( $out->child('v414-desktop.png') ) } );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'     => '4.14.0',
            'passed'      => scalar( @{$checks} ),
            'checks'      => $checks,
            'errors'      => $errors,
            'scoreLayout' => $score_layout
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
