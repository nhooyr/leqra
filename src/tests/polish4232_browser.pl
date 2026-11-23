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

my ($assets, $b, $c, $checks, $code, $errors, $html, $i, $js, $label, $manual, $out, $owners, $p, $pw, $root, $saved, $second, $web);
# v4.35.0 mobile-default and supplemental-fire regressions.
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = $root->child('tests/results/v4.35.0-polish');
$out->mkpath;
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script[^>]*src="[^"]+"[^>]*></script>', '', $html);
$html = replace_text($html, '</head>', ((('<style>' . $assets->child('theme.css')->slurp_utf8) . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location,window.__history);') . substr($js, ($i + 4)));
$checks = [];
$errors = [];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub setup {
    my ($page, $data) = @_;
    capture_event($page, 'pageerror', $errors, '(exc) => String(exc)');
    $page->setContent($html);
    evaluate_js($page, 'data=>{window.__location=new URL(\'http://example.test/?test=1\');window.__history={state:null,replaceState(){}};const store=obj=>({getItem:k=>Object.hasOwn(obj,k)?obj[k]:null,setItem:(k,v)=>obj[k]=String(v),removeItem:k=>delete obj[k]});Object.defineProperty(window,\'localStorage\',{value:store(data)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});}', $data);
    $page->addScriptTag({content => $assets->child('theme.js')->slurp_utf8});
    $page->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $page->addScriptTag({content => $js});
    wait_js($page, 'window.__test&&leqra.version===\'4.35.0\'');
}
sub tap {
    my ($page, $code) = @_;
    evaluate_js($page, 'c=>window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:c,bubbles:true}))', $code);
    $Leqra::Browser::HANDLE->await($page->waitForTimeout(45));
    evaluate_js($page, 'c=>window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:c,bubbles:true}))', $code);
    $Leqra::Browser::HANDLE->await($page->waitForTimeout(90));
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
$c = $b->newContext({viewport => {'width' => 390, 'height' => 844}, hasTouch => JSON::PP::true, isMobile => JSON::PP::true});
$p = $c->newPage();
main::setup($p, {'leqra.muted' => '1'});
main::check((value_eq(evaluate_js($p, 'leqra.getState().rules.mapSize'), 'compact')), 'Fresh mobile room defaults to Compact 7×7');
$c->close();
$saved = {'version' => 1, 'rules' => {'mode' => 'elimination', 'teamMode' => 'ffa', 'teamNames' => ['Team 1', 'Team 2', 'Team 3', 'Team 4'], 'teamColors' => [0, 1, 2, 3], 'mapSize' => 'large', 'scoreTarget' => 5, 'timeLimit' => 75, 'respawnSeconds' => 3, 'pickupRate' => 'superfast', 'friendlyFire' => JSON::PP::false, 'weapons' => ['rapid', 'scatter', 'shield', 'homing', 'grenade', 'speed', 'laser', 'scope', 'cannon', 'ghost']}};
$c = $b->newContext({viewport => {'width' => 390, 'height' => 844}, hasTouch => JSON::PP::true, isMobile => JSON::PP::true});
$p = $c->newPage();
main::setup($p, {'leqra.muted' => '1', 'leqra.roomRules.v1' => json_text($saved)});
main::check((value_eq(evaluate_js($p, 'leqra.getState().rules.mapSize'), 'large')), 'Saved mobile maze choice overrides Compact default');
$c->close();
$c = $b->newContext({viewport => {'width' => 1200, 'height' => 900}});
$p = $c->newPage();
main::setup($p, {'leqra.muted' => '1'});
$p->locator('#startRoomBtn')->click();
wait_js($p, 'leqra.getState().phase===\'playing\'');
for my $item (@{[['KeyC', 'C'], ['Enter', 'Enter']]}) {
    my $tuple_22_5 = $item;
    my $code = $tuple_22_5->[0];
    my $label = $tuple_22_5->[1];
    $Leqra::Browser::HANDLE->await($p->waitForTimeout(950));
    evaluate_js($p, '__test.clearBullets()');
    main::tap($p, $code);
    my $owners = evaluate_js($p, '__test.bullets.map(b=>b.owner)');
    main::check((contains_value($owners, 0)), ('Single-player ' . $label . ' fires Player 1'));
}
evaluate_js($p, '__test.createLocalRoom()');
$p->locator('#addLocalBtn')->click();
$second = evaluate_js($p, 'leqra.getState().room.players.find(p=>p.kind===\'local\').id');
$p->locator('#startRoomBtn')->click();
wait_js($p, 'leqra.getState().phase===\'playing\'');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(950));
evaluate_js($p, '__test.clearBullets()');
main::tap($p, 'KeyC');
$owners = evaluate_js($p, '__test.bullets.map(b=>b.owner)');
main::check((do { my $boolean_value = (contains_value($owners, 0)); truth_value($boolean_value) ? (!(contains_value($owners, $second))) : $boolean_value }), 'Two-player C fires Player 1 only');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(950));
evaluate_js($p, '__test.clearBullets()');
main::tap($p, 'Enter');
$owners = evaluate_js($p, '__test.bullets.map(b=>b.owner)');
main::check((do { my $boolean_value = (contains_value($owners, $second)); truth_value($boolean_value) ? (!(contains_value($owners, 0))) : $boolean_value }), 'Two-player Enter fires Player 2 only');
$p->locator('#roomBtn')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(50));
$manual = $p->locator('#manualContent')->innerText();
main::check((do { my $boolean_value = (contains_value($manual, 'C')); truth_value($boolean_value) ? (contains_value($manual, 'ENTER')) : $boolean_value }), 'Controls help displays supplemental fire keys');
main::check((!truth_value($errors)), ('No uncaught browser errors: ' . format_value($errors)));
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(json_text({'version' => '4.35.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors}, 1));
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
