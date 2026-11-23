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

my ($args, $assets, $browser, $c, $checks, $ctx, $data, $enabled_store, $errors, $height, $hi, $html, $i, $index, $js, $label, $legacy, $lo, $mode, $observed, $options, $out, $p, $p2, $parser, $pw, $rate, $raw, $report, $root, $saved, $silent, $sound, $store, $v, $web, $width, $x);
# v3.7.2 defaults, preference persistence, spawn timing and mobile UI regression.
# Optional: Python Playwright + Chromium. Uses the shipped scripts and deterministic
# simulation stepping; only URL/storage/audio-call observation are test adapters.
$parser = {};
$args = do { my %args = ('browser' => '/usr/bin/chromium', 'output' => 'test-output/defaults372'); my $help; GetOptions('browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl defaults372_browser.pl --browser --output
'; if ($help) { print 'Usage: perl defaults372_browser.pl --browser --output
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
my $tuple_21_0 = [[], []];
$checks = $tuple_21_0->[0];
$errors = $tuple_21_0->[1];
sub check {
    my ($value, $label) = @_;
    assert_ok($value, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script src="[^"]+" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
$i = rindex($js, '})()');
assert_ok((($i >= 0)), 'i >= 0');
$js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
sub load {
    my ($context, $storage, $broken) = @_;
    my ($p);
    $storage //= undef;
    $broken //= JSON::PP::false;
    $p = $context->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, '({data,broken})=>{
        window.__location=new URL(\'http://game.test/?test=1\');
        window.__store=data;window.__oscillators=0;
        const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,
            setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
        Object.defineProperty(window,\'localStorage\',{value:broken?{
            getItem(){throw Error(\'Storage blocked\');},setItem(){throw Error(\'Storage blocked\');}
        }:store(data)});
        Object.defineProperty(window,\'sessionStorage\',{value:store({})});
        window.requestAnimationFrame=()=>0;
        const A=window.AudioContext||window.webkitAudioContext;
        if(A){const create=A.prototype.createOscillator;A.prototype.createOscillator=function(){
            window.__oscillators++;return create.call(this);
        };}
    }', {'data' => (do { my $boolean_value = $storage; truth_value($boolean_value) ? $boolean_value : {} }), 'broken' => $broken});
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra && window.__test');
    return $p;
}
sub close {
    my ($p, $kind) = @_;
    $p->locator(('[data-close-dialog="' . $kind . 'Dialog"]'))->click();
}
sub controls {
    my ($p) = @_;
    $p->locator('#roomControlsBtn')->click();
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
eval {
    $ctx = $browser->newContext({viewport => {'width' => 1365, 'height' => 950}});
    $p = main::load($ctx);
    main::check((value_eq(evaluate_js($p, 'leqra.version'), '3.7.2')), 'Browser version 3.7.2');
    main::check((value_eq(evaluate_js($p, 'leqra.getState().rules.pickupRate'), 'superfast')), 'Fresh local room defaults to Super fast');
    main::controls($p);
    main::check($p->locator('#missileAudio')->isChecked(), 'Missile warning sound checked by default');
    main::check($p->locator('#missileVisuals')->isChecked(), 'Directional warnings still default on');
    $p->screenshot({path => format_value($out->child('settings-desktop.png'))});
    $p->locator('#missileAudio')->uncheck();
    $store = evaluate_js($p, '__store');
    main::check((value_eq(decode_json($store->{'leqra.feedback.v1'})->{'audio'}, JSON::PP::false)), 'Turning warning sound off persists');
    main::close($p, 'controls');
    $p2 = main::load($ctx, $store);
    main::controls($p2);
    main::check((!truth_value($p2->locator('#missileAudio')->isChecked())), 'Explicit saved sound-off remains off after reload');
    $p2->locator('#missileAudio')->check();
    $enabled_store = evaluate_js($p2, '__store');
    $p2->close();
    $p2 = main::load($ctx, $enabled_store);
    main::controls($p2);
    main::check($p2->locator('#missileAudio')->isChecked(), 'Explicit saved sound-on persists after reload');
    $p2->close();
    for my $item (@{[[{}, 'empty settings'], [{'visual' => JSON::PP::false, 'fps' => JSON::PP::true}, 'missing audio field']]}) {
        my $tuple_91_12 = $item;
        my $data = $tuple_91_12->[0];
        my $label = $tuple_91_12->[1];
        my $p2 = main::load($ctx, {'leqra.feedback.v1' => json_text($data)});
        main::controls($p2);
        main::check($p2->locator('#missileAudio')->isChecked(), ('Sound defaults on with ' . $label));
        if (truth_value((contains_value($data, 'visual')))) {
            main::check((do { my $boolean_value = (!truth_value($p2->locator('#missileVisuals')->isChecked())); truth_value($boolean_value) ? $p2->locator('#showFPS')->isChecked() : $boolean_value }), 'Other saved feedback preferences preserved');
        }
        $p2->close();
    }
    for $raw (@{['invalid JSON', 'null']}) {
        $p2 = main::load($ctx, {'leqra.feedback.v1' => $raw});
        main::controls($p2);
        main::check($p2->locator('#missileAudio')->isChecked(), ('Sound defaults on after ' . $raw));
        $p2->close();
    }
    $p2 = main::load($ctx, undef, JSON::PP::true);
    main::controls($p2);
    main::check($p2->locator('#missileAudio')->isChecked(), 'Sound defaults on when storage is unavailable');
    $p2->close();
    $p2 = main::load($ctx);
    $p2->locator('#startRoomBtn')->click();
    $Leqra::Browser::HANDLE->await($p2->waitForTimeout(100));
    $sound = evaluate_js($p2, '()=>{
            const T=__test;T.setPhase(\'playing\');T.clearBullets();
            T.addBullet({id:900,owner:1,kind:\'homing\',target:0,dead:false,x:200,y:200});
            const before=__oscillators;T.updateCombatFeedback(true);
            return {tones:__oscillators-before,warning:!document.querySelector(\'#missileWarning1\').hidden};
        }');
    main::check($sound->{'warning'}, 'Actual missile lock displays the existing warning');
    main::check((value_eq($sound->{'tones'}, 2)), 'Default warning schedules the two-tone lock sound');
    $p2->close();
    for my $item (@{[[{'leqra.muted' => '1'}, 'global mute'], [{'leqra.feedback.v1' => '{"audio":false}'}, 'warning disabled']]}) {
        my $tuple_122_12 = $item;
        my $data = $tuple_122_12->[0];
        my $label = $tuple_122_12->[1];
        my $p2 = main::load($ctx, $data);
        $p2->locator('#startRoomBtn')->click();
        $Leqra::Browser::HANDLE->await($p2->waitForTimeout(80));
        my $silent = evaluate_js($p2, '()=>{const T=__test;T.setPhase(\'playing\');T.clearBullets();T.addBullet({id:900,owner:1,kind:\'homing\',target:0,dead:false,x:200,y:200});const before=__oscillators;T.updateCombatFeedback(true);return __oscillators-before;}');
        main::check((value_eq($silent, 0)), ('No lock sound when ' . $label));
        $p2->close();
    }
    $p->locator('#roomRulesBtn')->click();
    $options = inspect_elements($p, '#rule-pickupRate option', '(xs)=>xs.map(x=>({value:x.value,text:x.textContent}))');
    main::check((value_eq([map { my $x = $_; $x->{'value'} } @{$options}], ['superfast', 'fast', 'normal', 'slow', 'off'])), 'Selector contains the new tier and all four existing choices');
    main::check((do { my $boolean_value = (contains_value($options->[0]->{'text'}, '1–2s')); truth_value($boolean_value) ? (contains_value($options->[0]->{'text'}, 'default')) : $boolean_value }), 'New tier has clear interval/default label');
    main::check((value_eq($p->locator('#rule-pickupRate')->inputValue(), 'superfast')), 'Rules editor preselects Super fast');
    $p->screenshot({path => format_value($out->child('rules-desktop.png'))});
    for $rate (@{['fast', 'normal', 'slow', 'off', 'superfast']}) {
        $p->locator('#rule-pickupRate')->selectOption($rate);
        $p->locator('#applyRulesBtn')->click();
        main::check((value_eq(evaluate_js($p, 'leqra.getState().rules.pickupRate'), $rate)), ('Host can apply ' . $rate));
        $p->locator('#roomRulesBtn')->click();
    }
    main::close($p, 'rules');
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetName')->fill('Super fast setup');
    $p->locator('#savePresetBtn')->click();
    $saved = evaluate_js($p, '__store');
    main::check((value_eq(decode_json($saved->{'leqra.presets.v1'})->{'items'}->[0]->{'rules'}->{'pickupRate'}, 'superfast')), 'Custom preset saves Super fast');
    $p2 = main::load($ctx, $saved);
    $p2->locator('#roomPresetsBtn')->click();
    $p2->locator('#presetSelect')->selectOption('saved:0');
    $p2->locator('#loadPresetBtn')->click();
    main::check((value_eq(evaluate_js($p2, 'leqra.getState().rules.pickupRate'), 'superfast')), 'Saved Super fast preset loads after reload');
    $p2->close();
    $legacy = decode_json($saved->{'leqra.presets.v1'});
    $legacy->{'items'}->[0]->{'rules'}->{'pickupRate'} = 'fast';
    $saved->{'leqra.presets.v1'} = json_text($legacy);
    $p2 = main::load($ctx, $saved);
    $p2->locator('#roomPresetsBtn')->click();
    $p2->locator('#presetSelect')->selectOption('saved:0');
    $p2->locator('#loadPresetBtn')->click();
    main::check((value_eq(evaluate_js($p2, 'leqra.getState().rules.pickupRate'), 'fast')), 'Older preset keeps its explicit Fast frequency');
    $p2->close();
    main::close($p, 'presets');
    for $index (@{[0 .. 5 - 1]}) {
        $p->locator('#roomPresetsBtn')->click();
        $p->locator('#presetSelect')->selectOption(('builtin:' . format_value($index)));
        $p->locator('#loadPresetBtn')->click();
        main::check((value_eq(evaluate_js($p, 'leqra.getState().rules.pickupRate'), 'superfast')), (('Built-in preset ' . format_value($index)) . ' inherits new default'));
    }
    for $mode (@{['elimination', 'ctf', 'koth']}) {
        for my $item (@{[['superfast', 1, 2], ['fast', 2, 3.5], ['normal', 4, 6], ['slow', 7, 10], ['off', 2, 3.5]]}) {
            my $tuple_160_16 = $item;
            my $rate = $tuple_160_16->[0];
            my $lo = $tuple_160_16->[1];
            my $hi = $tuple_160_16->[2];
            my $observed = evaluate_js($p, '({mode,rate,lo,hi})=>{
                    const T=__test;T.setPhase(\'menu\');
                    T.setLocalRules({...T.defaultRoomRules(),mode,teamMode:\'teams\',pickupRate:rate,weapons:[\'laser\']});
                    T.startRound();T.setPhase(\'playing\');
                    for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=999;}
                    const initial=T.pickups.length;
                    const beforeSteps=Math.round(lo*120)-1;
                    for(let i=0;i<beforeSteps;i++)T.update(1/120);
                    const before=T.pickups.length;
                    for(let i=0;i<2;i++)T.update(1/120);
                    const after=T.pickups.length;
                    const delays=[];
                    if(rate!==\'off\')for(let n=0;n<6;n++){
                        T.pickups.length=0;let elapsed=0;
                        while(!T.pickups.length&&elapsed<hi+.1){T.update(1/120);elapsed+=1/120;}
                        delays.push(elapsed);
                    }
                    for(let i=0;i<100;i++)T.spawnPower();
                    const result={initial,before,after,delays,cap:T.pickups.length,onlyLaser:T.pickups.every(x=>x.type===\'laser\')};
                    T.setPhase(\'menu\');return result;
                }', {'mode' => $mode, 'rate' => $rate, 'lo' => $lo, 'hi' => $hi});
            main::check((do { my $boolean_value = (value_eq($observed->{'initial'}, (truth_value((value_eq($rate, 'off'))) ? 0 : 2))); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($observed->{'before'}, $observed->{'initial'})); truth_value($boolean_value) ? (value_eq($observed->{'after'}, (truth_value((value_eq($rate, 'off'))) ? 0 : 3))) : $boolean_value } : $boolean_value }), ((($mode . ' ') . $rate) . ' starting count and first-delay boundary'));
            main::check((do { my $boolean_value = !scalar(grep { my $v = $_; !(((($lo - 0.02) <= $v) && ($v <= ($hi + 0.02)))) } @{$observed->{'delays'}}); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($observed->{'cap'}, (truth_value((value_eq($rate, 'off'))) ? 0 : 5))); truth_value($boolean_value) ? $observed->{'onlyLaser'} : $boolean_value } : $boolean_value }), ((($mode . ' ') . $rate) . ' repeated interval, weapon filter and five-pickup cap'));
        }
    }
    $ctx->close();
    for my $item (@{[[320, 568], [390, 844], [844, 390]]}) {
        my $tuple_186_12 = $item;
        my $width = $tuple_186_12->[0];
        my $height = $tuple_186_12->[1];
        my $c = $browser->newContext({viewport => {'width' => $width, 'height' => $height}, isMobile => JSON::PP::true, hasTouch => JSON::PP::true, deviceScaleFactor => 2});
        my $p = main::load($c);
        main::controls($p);
        main::check($p->locator('#missileAudio')->isChecked(), ('Mobile sound default ' . $width . 'x' . $height));
        main::close($p, 'controls');
        $p->locator('#roomRulesBtn')->click();
        $p->locator('#rule-pickupRate')->scrollIntoViewIfNeeded();
        main::check((value_eq($p->locator('#rule-pickupRate')->inputValue(), 'superfast')), ('Mobile frequency default ' . $width . 'x' . $height));
        main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth+1'), ('No horizontal page overflow ' . $width . 'x' . $height));
        main::check(evaluate_js($p, '()=>{const e=document.querySelector(\'#rule-pickupRate\'),s=getComputedStyle(e),c=document.createElement(\'canvas\').getContext(\'2d\');c.font=s.font;return c.measureText(e.selectedOptions[0].textContent).width<=e.clientWidth-parseFloat(s.paddingLeft)-parseFloat(s.paddingRight)-24;}'), ('Full interval label fits ' . $width . 'x' . $height));
        $p->screenshot({path => format_value($out->child(('rules-' . $width . 'x' . $height . '.png')))});
        main::close($p, 'rules');
        $c->close();
    }
    main::check((!truth_value($errors)), 'No uncaught browser errors');
    $report = {'version' => '3.7.2', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Chromium desktop/mobile emulation; exact assets, synthetic URL/storage, manual simulation stepping. Native AudioContext scheduling observed, not physical speaker validation.'};
    $out->child('results.json')->spew_utf8(json_text($report, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
$browser->close();
die $caught_error if $caught_error;
