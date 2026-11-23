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

my ( $assets, $b, $c, $checks, $errors, $html, $i, $js, $out, $p, $pw, $report, $root, $style, $web, $world );

# v4.22 focused UI, auto-save, integrated-chat and Ghost regression checks.
$root   = path($0)->absolute->parent(2);
$web    = $root->child('web');
$assets = asset_directory($web);
$out    = $root->child('tests/results/v4.22-polish');
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
$c = $b->newContext( { viewport => { 'width' => 1200, 'height' => 900 } } );
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
$p->setContent($html);
evaluate_js( $p,
'()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={};const st={getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]};Object.defineProperty(window,\'localStorage\',{value:st});Object.defineProperty(window,\'sessionStorage\',{value:st});}'
);
$p->addScriptTag( { content => $assets->child('theme.js')->slurp_utf8 } );
$p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
$p->addScriptTag( { content => $js } );
wait_js( $p, 'window.__test&&leqra.version===\'4.35.0\'' );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( $p->locator('#roomCallsignForm button')->count(), 0 ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#menuCallsignForm button')->count(), 0 ) )
              : $boolean_value;
        }
    ),
    'Callsign editors no longer require explicit Save buttons'
);
$p->locator('#roomCallsign')->fill('Blur Pilot');
$p->locator('#roomEyebrow')->click();
wait_js( $p, 'leqra.getState().room.players.some(p=>p.name===\'Blur Pilot\')' );
main::check( JSON::PP::true, 'Local callsign saves automatically when the field loses focus' );
$p->locator('#joinOtherBtn')->click();
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#joinRoomBtn')->count(), 1 ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#createRoomBtn')->count(), 0 ) )
              : $boolean_value;
        }
    ),
    'Join another room exposes one Join action and no redundant Create Room button'
);
$p->locator('#onlineBackBtn')->click();
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#roomCodeEditor button')->count(), 0 ) );
            truth_value($boolean_value)
              ? ( contains_value( $p->locator('#roomCodeEditor')->innerText(), 'Enter or when you leave' ) )
              : $boolean_value;
        }
    ),
    'Online room code editor is auto-save only'
);
$p->locator('#roomRulesBtn')->click();
wait_js( $p, 'document.querySelector(\'#rulesDialog\').open' );
$style = evaluate_js( $p->locator('#rulesDialog select')->first(),
    'e=>({pad:parseFloat(getComputedStyle(e).paddingRight),pos:getComputedStyle(e).backgroundPosition})' );
main::check(
    (
        do {
            my $boolean_value = ( ( $style->{'pad'} >= 44 ) );
            truth_value($boolean_value)
              ? (
                do {
                    my $boolean_value =
                      ( contains_value( $style->{'pos'}, '25px' ) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( contains_value( $style->{'pos'}, '19px' ) );
                }
              )
              : $boolean_value;
        }
    ),
    'Feature-menu dropdown arrows have extra right-side spacing'
);
$p->locator('#rulesDialog .dialog-close')->click();
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#enemyChatBtn')->count(), 0 ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#chatBtn')->count(), 1 ) )
              : $boolean_value;
        }
    ),
    'Chat uses one integrated header button'
);
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#chatOpponentToggle')->count(), 1 ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#chatTargetSwitch button')->count(), 0 ) )
              : $boolean_value;
        }
    ),
    'Opponent sending uses a compact in-chat toggle rather than a second chat button'
);
$world = {
    'width'  => 1008,
    'height' => 840,
    'cols'   => 12,
    'rows'   => 10,
    'walls'  => [
        { 'x' => (-4), 'y' => (-4), 'w' => 1016, 'h' => 8 },
        { 'x' => (-4), 'y' => 836,  'w' => 1016, 'h' => 8 },
        { 'x' => (-4), 'y' => (-4), 'w' => 8,    'h' => 848 },
        { 'x' => 1004, 'y' => (-4), 'w' => 8,    'h' => 848 },
        { 'x' => 248,  'y' => (-4), 'w' => 8,    'h' => 848 }
    ]
};
evaluate_js( $p, '(w)=>__test.setWorld(w)', $world );
main::check( ( value_eq( evaluate_js( $p, '__test.wallBetweenCenters(242,420,31,0)' ), JSON::PP::true ) ),
    'Ghost overlap across an interior wall is recognized as wall-separated' );
main::check( ( !truth_value($errors) ), ( 'No uncaught browser errors: ' . format_value($errors) ) );
$p->screenshot( { path => format_value( $out->child('v4.22-ui.png') ) } );
$c->close();
$b->close();
$report = {
    'version' => '4.35.0',
    'passed'  => scalar( @{$checks} ),
    'checks'  => $checks,
    'errors'  => $errors
};
$out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
