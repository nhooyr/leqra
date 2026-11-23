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

my ($a, $ap, $assets, $browser, $c, $checks, $contexts, $custom, $errors, $fallback, $html, $i, $js, $out, $p, $preset, $pw, $report, $room, $root, $store, $stored, $web, $x);
# v4.7 isolated-browser regression: local-room rules persist across reload-equivalent loads.
$ap = {};
$a = do { my %args = ('output' => 'test-output/local-rules47'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl local_rules47_browser.pl --output
'; if ($help) { print 'Usage: perl local_rules47_browser.pl --output
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($a->{'output'});
$out->mkpath;
$html = replace_text(replace_re('<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8), '</head>', ((('<style>' . $assets->child('theme.css')->slurp_utf8) . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location,window.__history);') . substr($js, ($i + 4)));
$checks = [];
$errors = [];
$contexts = [];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub load {
    my ($browser, $store) = @_;
    my ($c, $f, $p);
    $store //= undef;
    $c = $browser->newContext({viewport => {'width' => 1100, 'height' => 820}, colorScheme => 'dark'});
    push(@{$contexts}, $c);
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, 'a=>{window.__location=new URL(\'https://leqra.test/?test=1\');window.__history={state:null,replaceState(){}};window.__store=a.store||{};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>window.__store[k]??null,setItem:(k,v)=>window.__store[k]=String(v),removeItem:k=>delete window.__store[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}', {'store' => (do { my $boolean_value = $store; truth_value($boolean_value) ? $boolean_value : {} })});
    for $f (@{['theme.js', 'netcode.js']}) {
        $p->addScriptTag({content => $assets->child($f)->slurp_utf8});
    }
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.__test && leqra.version==="4.7.0"');
    return $p;
}
sub state {
    my ($p) = @_;
    return evaluate_js($p, 'leqra.getState()');
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
eval {
    $p = main::load($browser, {'leqra.name' => 'PILOT', 'leqra.muted' => '1'});
    $custom = {'mode' => 'ctf', 'teamMode' => 'teams', 'teamNames' => ['NEON WOLVES', 'ORBIT', 'COBALT CREW', 'NIGHT SHIFT'], 'teamColors' => [7, 5, 1, 3], 'mapSize' => 'giant', 'scoreTarget' => 9, 'timeLimit' => 333, 'respawnSeconds' => 7, 'pickupRate' => 'slow', 'friendlyFire' => JSON::PP::true, 'weapons' => ['shield', 'speed', 'laser', 'scope', 'ghost']};
    evaluate_js($p, '(r)=>__test.setLocalRules(r)', $custom);
    $stored = evaluate_js($p, 'JSON.parse(__store[\'leqra.roomRules.v1\'])');
    main::check((do { my $boolean_value = (value_eq($stored->{'version'}, 1)); truth_value($boolean_value) ? (value_eq($stored->{'rules'}, $custom)) : $boolean_value }), 'applied local rules are written to versioned localStorage');
    $store = evaluate_js($p, '({...__store})');
    $p->close();
    $p = main::load($browser, $store);
    main::check((value_eq(main::state($p)->{'rules'}, $custom)), 'map, teams, names/colors and match rules restore after reload');
    $room = main::state($p)->{'room'};
    main::check((do { my $boolean_value = (value_eq($room->{'players'}->[0]->{'team'}, 1)); truth_value($boolean_value) ? !scalar(grep { my $x = $_; !((value_eq($x->{'team'}, 2))) } @{array_slice($room->{'players'}, 1, undef)}) : $boolean_value }), 'restored Teams rules build a valid default local lineup');
    $p->locator('#roomRulesBtn')->click();
    main::check((do { my $boolean_value = (value_eq($p->locator('#roomMapSize')->inputValue(), 'giant')); truth_value($boolean_value) ? (value_eq($p->locator('#rule-teamName1')->inputValue(), 'NEON WOLVES')) : $boolean_value }), 'restored values populate Rules controls');
    $p->locator('[data-close-dialog="rulesDialog"]')->click();
    $preset = {%{$custom}, 'mode' => 'koth', 'teamMode' => 'ffa', 'mapSize' => 'compact', 'scoreTarget' => 44, 'timeLimit' => 222, 'respawnSeconds' => 4, 'pickupRate' => 'superfast', 'friendlyFire' => JSON::PP::false, 'teamNames' => ['A', 'B', 'C', 'D'], 'teamColors' => [0, 1, 2, 3], 'weapons' => ['rapid', 'scatter']};
    evaluate_js($p, '(r)=>__test.applyLocalPreset({rules:r,roster:[{kind:"human",name:"PILOT",team:0}]})', $preset);
    $store = evaluate_js($p, '({...__store})');
    $p->close();
    $p = main::load($browser, $store);
    main::check((value_eq(main::state($p)->{'rules'}, $preset)), 'loading a preset updates the automatically restored current rules');
    $store = evaluate_js($p, '({...__store})');
    $store->{'leqra.roomRules.v1'} = '{bad json';
    $p->close();
    $p = main::load($browser, $store);
    $fallback = main::state($p)->{'rules'};
    main::check((do { my $boolean_value = (value_eq($fallback->{'mapSize'}, 'large')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($fallback->{'mode'}, 'elimination')); truth_value($boolean_value) ? (value_eq($fallback->{'teamMode'}, 'ffa')) : $boolean_value } : $boolean_value }), 'corrupt stored rules safely fall back to defaults');
    main::check((!truth_value($errors)), 'no uncaught browser errors');
    $p->screenshot({path => format_value($out->child('restored-room.png'))});
1;
};
my $caught_error = $@;
for $c (@{$contexts}) {
    eval {
        $c->close();
    1;
    };
    if ($@) {
    }
}
$browser->close();
die $caught_error if $caught_error;
$report = {'version' => '4.7.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors};
$out->child('results.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text($report, 1)), "\n");
