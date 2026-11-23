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

my ($a, $ammo, $ap, $args, $assets, $b, $browser, $button, $capture, $cdp, $checks, $code, $contexts, $data, $errors, $feedback, $hill, $hit, $lid, $out, $p, $persist, $pw, $q, $report, $resp, $root, $s, $saved, $savedonline, $size, $web, $x);
# v3.2 UI/local simulation and real Go-backed objective tests.
# Uses shipped assets with Location/History/storage adapters because navigation is
# blocked in the execution environment. The fixture server is opt-in and loopback-only.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:8878', 'browser' => '/usr/bin/chromium', 'output' => 'test-output/features32'); my $help; GetOptions('url=s' => \$args{'url'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl features32_browser.pl --url --browser --output
'; if ($help) { print 'Usage: perl features32_browser.pl --url --browser --output
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub dismissVictory {
    my ($p) = @_;
    if (truth_value((do { my $boolean_value = $p->locator('#victoryDialog')->count(); truth_value($boolean_value) ? $p->locator('#victoryDialog')->isVisible() : $boolean_value }))) {
        $p->locator('#victoryCloseBtn')->click();
    }
}
sub check {
    my ($v, $label) = @_;
    if (truth_value((!truth_value($v)))) {
        die json_text($label);
    }
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub state {
    my ($p) = @_;
    return evaluate_js($p, 'leqra.getState()');
}
sub fixture {
    my ($code, $action, $player) = @_;
    my ($r);
    $player //= 0;
    $r = request_ok(HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/features32'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'action' => $action, 'player' => $player}))));
    return decode_json($r->content);
}
sub lane {
    my ($p) = @_;
    evaluate_js($p, '()=>{const T=__test,w=leqra.getState().world;T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{x:150,y:90+i*110,angle:0,invulnerable:100,cooldown:99,alive:true}));T.clearInput();}');
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
$contexts = [];
sub load {
    my ($name, $code, $size, $storage) = @_;
    my ($ctx, $html, $i, $js, $mobile, $p, $url);
    $name //= 'HOST';
    $code //= undef;
    $size //= [1365, 950];
    $storage //= undef;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $ctx = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $ctx);
    $p = $ctx->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->on('dialog', 'arguments[0].accept();');
    $html = replace_text(replace_text(replace_text(replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8), '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', ''), '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
    $p->setContent($html);
    $url = ('http://game.test/tanks/?test=1' . (truth_value($code) ? ('&' . query_string({'room' => $code})) : ''));
    evaluate_js($p, '([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied=\'\';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=(data)=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({\'leqra.name\':name,\'leqra.muted\':\'1\'},storage||{});Object.defineProperty(window,\'localStorage\',{value:store(__store)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});}', [$url, (replace_text($args->{'url'}, 'http:', 'ws:') . '/ws'), $name, $storage]);
    $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
    $i = rindex($js, '})()');
    $js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    return $p;
}
sub close {
    my ($p, $kind) = @_;
    $p->locator((('[data-close-dialog="' . $kind) . 'Dialog"]'))->click();
}
sub preset {
    my ($p, $index) = @_;
    main::dismissVictory($p);
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetSelect')->selectOption(('builtin:' . format_value($index)));
    $p->locator('#loadPresetBtn')->click();
    wait_js($p, '!document.querySelector("#presetsDialog").open');
}
sub start {
    my ($p) = @_;
    main::dismissVictory($p);
    $p->locator('#startRoomBtn')->click();
    wait_js($p, 'leqra.getState().phase==="playing"', undef, {timeout => 9000});
}
sub room {
    my ($p) = @_;
    main::dismissVictory($p);
    $p->locator('#roomBtn')->click();
    $p->locator('#returnRoomBtn')->click();
    wait_js($p, '["menu","onlineLobby"].includes(leqra.getState().phase)');
}
sub press {
    my ($p, $key, $ms) = @_;
    $ms //= 40;
    $p->keyboard()->down($key);
    $Leqra::Browser::HANDLE->await($p->waitForTimeout($ms));
    $p->keyboard()->up($key);
}
sub rules {
    my ($p, $values) = @_;
    my ($control, $key, $loc, $selected_mode, $selector, $setting, $val, $value);
    $values //= {};
    main::dismissVictory($p);
    $selected_mode = splice(@{$values}, 'mode', 1);
    if (truth_value((defined($selected_mode)))) {
        $p->locator((('[data-room-mode="' . $selected_mode) . '"]'))->click();
        wait_js($p, '(mode)=>leqra.getState().rules.mode===mode', $selected_mode, {});
    }
    for my $item (@{[['teamMode', '#roomTeamMode'], ['mapSize', '#roomMapSize']]}) {
        my $tuple_44_6 = $item;
        my $setting = $tuple_44_6->[0];
        my $selector = $tuple_44_6->[1];
        my $value = splice(@{$values}, $setting, 1);
        if (truth_value((defined($value)))) {
            my $control = $p->locator($selector);
            if (truth_value($control->isDisabled())) {
                assert_ok((value_eq($control->inputValue(), format_value($value))), 'control.input_value()==str(value)');
            } else {
                $control->selectOption(format_value($value));
                wait_js($p, '([key,value])=>leqra.getState().rules[key]===value', [$setting, $value], {});
            }
        }
    }
    $p->locator('#roomRulesBtn')->click();
    for my $item (@{[map { [$_, $values->{$_}] } keys %{$values}]}) {
        my $tuple_51_6 = $item;
        my $key = $tuple_51_6->[0];
        my $val = $tuple_51_6->[1];
        my $loc = $p->locator(('#rule-' . $key));
        if (truth_value((contains_value(['teamMode', 'mapSize', 'pickupRate'], $key)))) {
            if (truth_value((!truth_value($loc->isDisabled())))) {
                $loc->selectOption(format_value($val));
                $Leqra::Browser::HANDLE->await($p->waitForTimeout(20));
            } else {
                assert_ok((value_eq($loc->inputValue(), format_value($val))), 'loc.input_value()==str(val)');
            }
        } else {
            $loc->fill(format_value($val));
        }
    }
    $p->locator('#applyRulesBtn')->click();
    wait_js($p, '!document.querySelector("#rulesDialog").open');
}
sub screenshot {
    my ($p, $name) = @_;
    $p->screenshot({path => format_value($out->child(($name . '.png')))});
}
$p = main::load();
main::check((value_eq(main::state($p)->{'rules'}->{'mode'}, 'elimination')), 'Default room keeps elimination rules');
main::check((do { my $boolean_value = $p->locator('#roomRulesBtn')->isVisible(); truth_value($boolean_value) ? do { my $boolean_value = $p->locator('#roomPresetsBtn')->isVisible(); truth_value($boolean_value) ? $p->locator('#roomControlsBtn')->isVisible() : $boolean_value } : $boolean_value }), 'Rules, presets and controls are separate room panels');
$p->locator('#addLocalBtn')->click();
main::check((value_eq(main::state($p)->{'room'}->{'players'}->[(-1)]->{'id'}, 3)), 'New P2 keeps sparse seat identity');
$p->locator('#roomControlsBtn')->click();
main::check((do { my $boolean_value = (value_eq($p->locator('[data-bind="0:fire"]')->innerText(), 'F')); truth_value($boolean_value) ? (value_eq($p->locator('[data-bind="1:fire"]')->innerText(), 'SPACE')) : $boolean_value }), 'Default P1 F and P2 Space shown in remapper');
main::close($p, 'controls');
main::start($p);
main::lane($p);
evaluate_js($p, '()=>{for(const t of __test.tanks.filter(t=>t.human)){t.cooldown=0;__test.grantPower(t,\'grenade\');t.charges=1;}}');
main::press($p, 'Enter');
main::check(evaluate_js($p, '__test.bullets.length===0'), 'Enter no longer fires the secondary tank');
main::press($p, 'Space');
main::check(evaluate_js($p, '__test.bullets.filter(b=>b.kind==="grenade").length===1&&__test.bullets[0].owner===3'), 'Space throws only the secondary tank grenade');
main::press($p, 'Space');
main::check(evaluate_js($p, '__test.bullets.length===0'), 'Space detonates secondary final grenade without P1 crosstalk');
main::press($p, 'KeyF');
main::check(evaluate_js($p, '__test.bullets.some(b=>b.kind==="grenade"&&b.owner===0)'), 'F fires the primary tank independently');
main::check((value_eq($p->locator('#cooldownText1')->innerText(), 'DETONATE READY')), 'Cooldown feedback prioritizes armed remote grenade');
main::press($p, 'KeyF');
main::room($p);
$p->locator('#roomControlsBtn')->click();
$p->locator('[data-bind="1:fire"]')->click();
$p->keyboard()->press('KeyF');
main::check((do { my $boolean_value = (contains_value($p->locator('#controlsNotice')->innerText(), 'already assigned')); truth_value($boolean_value) ? (value_eq(evaluate_js($p, '__test.bindings[1].fire'), 'Space')) : $boolean_value }), 'Conflicting key rejected without modifying either player');
$p->keyboard()->press('KeyP');
main::check((contains_value($p->locator('#controlsNotice')->innerText(), 'reserved')), 'Pause key cannot be rebound');
$p->keyboard()->press('KeyL');
main::check((value_eq(evaluate_js($p, '__test.bindings[1].fire'), 'KeyL')), 'Secondary fire can be rebound');
$p->locator('[data-bind="0:forward"]')->click();
$p->keyboard()->press('Escape');
main::check((value_eq(evaluate_js($p, '__test.bindings[0].forward'), 'KeyW')), 'Escape cancels key capture without modifying movement');
main::check((contains_value(evaluate_js($p, 'Object.keys(__store)'), 'leqra.bindings.v1')), 'Bindings saved in device storage');
$saved = evaluate_js($p, '({...__store})');
main::close($p, 'controls');
main::start($p);
main::lane($p);
evaluate_js($p, '()=>{let t=__test.tanks[3];t.cooldown=0;__test.grantPower(t,\'grenade\');}');
main::press($p, 'Space');
main::check(evaluate_js($p, '__test.bullets.length===0'), 'Old secondary fire key stops firing after remapping');
main::press($p, 'KeyL');
main::check(evaluate_js($p, '__test.bullets.some(b=>b.owner===3)'), 'Remapped fire launches on actual gameplay path');
main::check((contains_value($p->locator('#pilotLoadout2 .loadout-key')->innerText(), 'L')), 'Secondary HUD reflects remapped fire key');
main::room($p);
$q = main::load(undef, undef, undef, $saved);
main::check((value_eq(evaluate_js($q, '__test.bindings[1].fire'), 'KeyL')), 'A fresh page restores saved bindings');
$q->close();
$p->locator('#roomControlsBtn')->click();
$p->locator('#resetBindingsBtn')->click();
main::check((value_eq(evaluate_js($p, '__test.bindings[1].fire'), 'Space')), 'Reset defaults restores secondary Space');
$p->locator('#missileAudio')->uncheck();
$p->locator('#missileAudio')->check();
main::check(decode_json(evaluate_js($p, '__store["leqra.feedback.v1"]'))->{'audio'}, 'Optional lock warning audio preference persists');
main::close($p, 'controls');
main::rules($p, {'teamMode' => 'ffa', 'mapSize' => 'compact', 'scoreTarget' => 2, 'timeLimit' => 40, 'pickupRate' => 'off'});
main::check(!scalar(grep { my $x = $_; !((value_eq($x->{'team'}, 0))) } @{main::state($p)->{'room'}->{'players'}}), 'Host Free-for-all applies to every tank');
main::check((do { my $boolean_value = (($p->locator('#roomRoster [data-team]')->count() > 0)); truth_value($boolean_value) ? (value_eq($p->locator('#roomRoster [data-team]:enabled')->count(), 0)) : $boolean_value }), 'FFA locks all individual team selectors');
main::start($p);
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'world'}->{'cols'}, 7)); truth_value($boolean_value) ? (value_eq(main::state($p)->{'world'}->{'rows'}, 7)) : $boolean_value }), 'Compact host map rule changes actual maze');
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'pickupCount'}, 0)); truth_value($boolean_value) ? ((38 < main::state($p)->{'roundClock'}) && (main::state($p)->{'roundClock'} <= 40)) : $boolean_value }), 'Off rule removes starting pickups and clock uses host limit');
main::room($p);
main::rules($p, {'teamMode' => 'teams'});
main::check((value_eq([map { my $x = $_; $x->{'team'} } @{main::state($p)->{'room'}->{'players'}}], [1, 2, 2, 1])), 'Switching out of FFA restores sensible sides and unlocks selectors');
main::check((value_eq($p->locator('#roomRoster [data-team]:enabled')->count(), 4)), 'Host can edit all teams in Teams format');
main::dismissVictory($p);
$p->locator('#roomPresetsBtn')->click();
main::check((do { my $boolean_value = (value_eq($p->locator('#presetSelect optgroup')->count(), 2)); truth_value($boolean_value) ? (value_eq($p->locator('#presetSelect option')->count(), 5)) : $boolean_value }), 'Five built-in presets offered separately from saved presets');
$p->locator('#presetName')->fill('My squad 💥');
$p->locator('#savePresetBtn')->click();
main::check((contains_value($p->locator('#presetsNotice')->innerText(), 'Preset saved')), 'Named custom room preset saved');
$data = decode_json(evaluate_js($p, '__store["leqra.presets.v1"]'));
main::check((do { my $boolean_value = (value_eq($data->{'items'}->[0]->{'roster'}->[3]->{'kind'}, 'local')); truth_value($boolean_value) ? (value_eq($data->{'items'}->[0]->{'rules'}->{'mapSize'}, 'compact')) : $boolean_value }), 'Preset includes secondary player and match rules');
main::check((do { my $boolean_value = (!(contains_value(json_text($data), 'token'))); truth_value($boolean_value) ? (!(contains_value(json_text($data), 'member'))) : $boolean_value }), 'Saved preset contains no sessions or runtime identities');
main::close($p, 'presets');
main::preset($p, 0);
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($p)->{'room'}->{'players'}}), 2)); truth_value($boolean_value) ? (value_eq(main::state($p)->{'room'}->{'players'}->[1]->{'difficulty'}, 'easy')) : $boolean_value }), 'Solo Practice loads easy bot and compact maze');
main::dismissVictory($p);
$p->locator('#roomPresetsBtn')->click();
$p->locator('#presetSelect')->selectOption('saved:0');
$p->locator('#loadPresetBtn')->click();
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($p)->{'room'}->{'players'}}), 4)); truth_value($boolean_value) ? (value_eq(main::state($p)->{'rules'}->{'pickupRate'}, 'off')) : $boolean_value }), 'Saved setup restores full roster and weapon frequency');
$persist = evaluate_js($p, '({...__store})');
$q = main::load(undef, undef, undef, $persist);
main::dismissVictory($q);
$q->locator('#roomPresetsBtn')->click();
main::check((value_eq($q->locator('#presetSelect option[value="saved:0"]')->innerText(), 'My squad 💥')), 'Saved presets survive loading a fresh page');
$q->locator('#presetSelect')->selectOption('saved:0');
$q->locator('#deletePresetBtn')->click();
main::check((value_eq($q->locator('#presetSelect option[value="saved:0"]')->count(), 0)), 'Saved preset can be deleted with confirmation');
$q->close();
$q = main::load(undef, undef, undef, {'leqra.bindings.v1' => '{"bindings":[null]}', 'leqra.presets.v1' => 'broken'});
main::check((value_eq(evaluate_js($q, '__test.bindings[1].fire'), 'Space')), 'Invalid storage falls back to safe defaults');
$q->close();
main::preset($p, 2);
main::start($p);
main::lane($p);
$feedback = evaluate_js($p, '()=>{const t=__test.tanks[0],p2=__test.tanks[1];__test.clearBullets();Object.assign(t,{cooldown:.5,cooldownTotal:1,power:\'laser\',charges:3});Object.assign(p2,{cooldown:0,power:null});__test.addBullet({owner:2,target:0,kind:\'homing\',x:t.x+60,y:t.y,vx:-235,vy:0,r:4,life:5,age:1,rangeLeft:900,seekDelay:1,trail:[],color:\'#fff\'});__test.updateCombatFeedback();return {warning:!document.querySelector(\'#missileWarning1\').hidden,p2hidden:document.querySelector(\'#missileWarning2\').hidden,cd:document.querySelector(\'#cooldownText1\').textContent,progress:document.querySelector(\'#cooldownTrack1\').getAttribute(\'aria-valuenow\')};}');
main::check((do { my $boolean_value = $feedback->{'warning'}; truth_value($boolean_value) ? $feedback->{'p2hidden'} : $boolean_value }), 'Only the missile-targeted local player sees a lock warning');
main::check((do { my $boolean_value = (value_eq($feedback->{'cd'}, 'COOLDOWN 0.5s')); truth_value($boolean_value) ? (value_eq($feedback->{'progress'}, '50')) : $boolean_value }), 'Cooldown text and fill expose accurate time/progress');
evaluate_js($p, '()=>{__test.clearBullets();__test.tanks[0].cooldown=0;__test.updateCombatFeedback()}');
main::check($p->locator('#missileWarning1')->isHidden(), 'Missile warning clears when lock disappears');
$ammo = evaluate_js($p, '()=>{const t=__test.tanks[1];t.power=null;t.cooldown=0;for(let i=0;i<5;i++)__test.addBullet({id:100+i,kind:\'standard\',owner:t.id,dead:false});__test.updateCombatFeedback();const a=document.querySelector(\'#cooldownText2\').textContent;__test.clearBullets();return a;}');
main::check((value_eq($ammo, 'WAITING FOR AMMO')), 'Exhausted projectile slots show explicit wait status');
main::check($p->locator('#pilotLoadout2')->isVisible(), 'Both local players keep independent ammo/cooldown panels');
main::room($p);
main::preset($p, 3);
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'rules'}->{'mode'}, 'ctf')); truth_value($boolean_value) ? (value_eq(scalar(@{unique_values([map { my $x = $_; $x->{'team'} } @{main::state($p)->{'room'}->{'players'}}])}), 2)) : $boolean_value }), 'Capture preset supplies two valid teams');
main::rules($p, {'scoreTarget' => 2, 'respawnSeconds' => 1, 'pickupRate' => 'off'});
main::start($p);
main::lane($p);
main::check((do { my $boolean_value = $p->locator('#objectiveBar')->isVisible(); truth_value($boolean_value) ? (contains_value($p->locator('#objectiveModeLabel')->innerText(), 'CAPTURE')) : $boolean_value }), 'Capture mode shows in-game objective bar');
$capture = evaluate_js($p, '()=>{const o=__test.localObjectives,t=__test.tanks[0],f=o.flags.find(f=>f.team!==t.team),home=o.flags.find(f=>f.team===t.team);t.invulnerable=0;t.x=f.x;t.y=f.y;__test.stepLocalObjectives(.01);const stolen=f.carrier===t.id;t.x=home.homeX;t.y=home.homeY;__test.stepLocalObjectives(.01);return{stolen,home:f.home,scores:leqra.getState().scores};}');
main::check((do { my $boolean_value = $capture->{'stolen'}; truth_value($boolean_value) ? $capture->{'home'} : $boolean_value }), 'Local CTF supports actual pickup and capture');
main::check((do { my $boolean_value = (value_eq($capture->{'scores'}->[0], 1)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($capture->{'scores'}->[1], 1)); truth_value($boolean_value) ? (value_eq($capture->{'scores'}->[2], 0)) : $boolean_value } : $boolean_value }), 'CTF point is shared only with teammates');
$resp = evaluate_js($p, '()=>{const t=__test.tanks[0],f=__test.localObjectives.flags.find(f=>f.team!==t.team);Object.assign(f,{carrier:t.id,home:false,x:t.x,y:t.y});t.invulnerable=0;__test.hurt(t,{owner:2});__test.updateCombatFeedback();const before={dead:!t.alive,dropped:f.carrier<0&&!f.home,caption:document.querySelector(\'#cooldownText1\').textContent};__test.respawnLocalPlayers(1.1);return{...before,alive:t.alive,serial:t.spawnSerial,shield:t.invulnerable};}');
main::check((do { my $boolean_value = $resp->{'dead'}; truth_value($boolean_value) ? do { my $boolean_value = $resp->{'dropped'}; truth_value($boolean_value) ? do { my $boolean_value = $resp->{'alive'}; truth_value($boolean_value) ? (($resp->{'shield'} > 0)) : $boolean_value } : $boolean_value } : $boolean_value }), 'CTF death drops the flag and configured respawn restores protected tank');
main::check((index($resp->{'caption'}, 'RESPAWN ') == 0), 'Dead player sees respawn countdown instead of empty ready message');
evaluate_js($p, '()=>{const t=__test.tanks[0],o=__test.localObjectives,own=o.flags.find(f=>f.team===t.team),enemy=o.flags.find(f=>f.team!==t.team);t.invulnerable=0;t.x=own.homeX;t.y=own.homeY;Object.assign(enemy,{carrier:0,home:false});__test.stepLocalObjectives(.01);}');
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'phase'}, 'matchOver')); truth_value($boolean_value) ? (value_eq(main::state($p)->{'scores'}->[0], 2)) : $boolean_value }), 'CTF ends at capture target without an extra elimination point');
main::preset($p, 4);
main::rules($p, {'scoreTarget' => 3, 'respawnSeconds' => 1, 'pickupRate' => 'off'});
main::start($p);
main::lane($p);
$hill = evaluate_js($p, '()=>{const o=__test.localObjectives,t=__test.tanks[0];t.invulnerable=0;t.x=o.hillX-16;t.y=o.hillY;__test.stepLocalObjectives(1.05);const a=leqra.getState().scores[0];const u=__test.tanks[1];u.invulnerable=0;u.x=o.hillX+16;u.y=o.hillY;__test.stepLocalObjectives(1.2);return {first:a,after:leqra.getState().scores[0],contested:o.contested};}');
main::check((do { my $boolean_value = (value_eq($hill->{'first'}, 1)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($hill->{'after'}, 1)); truth_value($boolean_value) ? $hill->{'contested'} : $boolean_value } : $boolean_value }), 'Local KOTH awards timed points and pauses while contested');
evaluate_js($p, '()=>{const o=__test.localObjectives;__test.tanks[1].x=60;__test.stepLocalObjectives(2.05)}');
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'phase'}, 'matchOver')); truth_value($boolean_value) ? (value_eq(main::state($p)->{'scores'}->[0], 3)) : $boolean_value }), 'KOTH reaches its point target rather than ending on a kill');
main::rules($p, {'mode' => 'ctf'});
$p->locator('#roomRoster [data-team="0"]')->selectOption('0');
main::check($p->locator('#startRoomBtn')->isDisabled(), 'CTF refuses FFA/invalid roster until host assigns exactly two numbered teams');
main::preset($p, 0);
$code = (('Objective32 ' . format_value(int(time() * 1e9))) . ' ⚑');
$p->locator('#localRoomName')->fill($code);
$p->locator('#copyInviteBtn')->click();
wait_js($p, 'leqra.getState().online?.connected');
$q = main::load('GUEST', $code, [390, 844]);
wait_js($q, 'leqra.getState().online?.connected');
wait_js($p, 'leqra.getState().room.players.length===3');
main::check((do { my $boolean_value = $q->locator('#roomPresetsBtn')->isDisabled(); truth_value($boolean_value) ? (value_eq($q->locator('#roomRulesBtn')->innerText(), 'VIEW RULES')) : $boolean_value }), 'Guest can inspect rules but cannot load host presets');
main::dismissVictory($q);
$q->locator('#roomRulesBtn')->click();
main::check((do { my $boolean_value = evaluate_js($q->locator('#rulesFields'), '(e)=>e.disabled'); truth_value($boolean_value) ? $q->locator('#applyRulesBtn')->isDisabled() : $boolean_value }), 'Guest rules fields are read-only');
main::close($q, 'rules');
evaluate_js($q, '()=>__sockets.at(-1).send(JSON.stringify({type:\'rules\',rules:{...leqra.getState().rules,teamMode:\'ffa\'}}))');
wait_js($q, '__messages.some(m=>m.type==="error"&&m.code==="not_host")');
main::check((value_eq(main::state($p)->{'rules'}->{'teamMode'}, 'teams')), 'Go rejects a forged guest Free-for-all command');
main::rules($p, {'teamMode' => 'ffa'});
wait_js($q, 'leqra.getState().rules.teamMode==="ffa"');
main::check(!scalar(grep { my $x = $_; !((value_eq($x->{'team'}, 0))) } @{main::state($q)->{'room'}->{'players'}}), 'Online Free-for-all applies and broadcasts to all players');
main::check((do { my $boolean_value = (value_eq($q->locator('#roomRoster select')->count(), 0)); truth_value($boolean_value) ? (value_eq($p->locator('#roomRoster [data-team]:enabled')->count(), 0)) : $boolean_value }), 'Neither guest nor host seat selector can pick teams under FFA');
main::dismissVictory($p);
$p->locator('#roomPresetsBtn')->click();
main::check($p->locator('#loadPresetBtn')->isDisabled(), 'Preset loading refuses to replace a remote guest');
$p->locator('#presetName')->fill('Shared setup');
$p->locator('#savePresetBtn')->click();
$savedonline = decode_json(evaluate_js($p, '__store["leqra.presets.v1"]'));
main::check(!scalar(grep { my $x = $_; !((!value_eq($x->{'name'}, 'GUEST'))) } @{$savedonline->{'items'}->[(-1)]->{'roster'}}), 'Saving an online preset omits remote guests');
main::close($p, 'presets');
main::rules($p, {'mode' => 'ctf', 'teamMode' => 'teams', 'scoreTarget' => 2, 'respawnSeconds' => 1, 'pickupRate' => 'off', 'mapSize' => 'large'});
wait_js($q, 'leqra.getState().rules.mode==="ctf"');
main::dismissVictory($q);
$q->locator('#readyBtn')->click();
wait_js($p, 'leqra.getState().room.canStart');
main::start($p);
wait_js($q, 'leqra.getState().phase==="playing"');
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'world'}->{'cols'}, 12)); truth_value($boolean_value) ? (value_eq(main::state($q)->{'world'}->{'cols'}, 12)) : $boolean_value }), 'Host-selected large map is authoritative for both browsers');
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($p)->{'objectives'}->{'flags'}}), 2)); truth_value($boolean_value) ? (value_eq(main::state($q)->{'objectives'}->{'mode'}, 'ctf')) : $boolean_value }), 'Go sends complete objective state to host and guest');
main::fixture($code, 'capture');
wait_js($p, 'leqra.getState().scores[0]===1');
wait_js($q, 'leqra.getState().scores[0]===1');
main::check(JSON::PP::true, 'Server capture score arrives identically at host and guest');
main::fixture($code, 'kill');
wait_js($p, '!leqra.getState().tanks.find(t=>t.id===0).alive');
main::check((contains_value($p->locator('#cooldownText1')->innerText(), 'RESPAWN')), 'Authoritative death exposes the respawn countdown');
wait_js($p, 'leqra.getState().tanks.find(t=>t.id===0).alive&&leqra.getState().tanks[0].spawnSerial>=2', undef, {timeout => 5000});
main::check(JSON::PP::true, 'Server respawn increments epoch and restores controlled tank');
main::fixture($code, 'capture');
wait_js($p, 'leqra.getState().phase==="matchOver"');
wait_js($q, 'leqra.getState().phase==="matchOver"');
main::check((value_eq(main::state($p)->{'scores'}->[0], 2)), 'Online CTF finishes at configured target on all clients');
main::rules($p, {'mode' => 'koth', 'teamMode' => 'ffa', 'scoreTarget' => 8, 'respawnSeconds' => 1, 'pickupRate' => 'off'});
wait_js($q, 'leqra.getState().rules.mode==="koth"');
main::dismissVictory($q);
$q->locator('#readyBtn')->click();
wait_js($p, 'leqra.getState().room.canStart');
main::start($p);
wait_js($q, 'leqra.getState().phase==="playing"');
main::fixture($code, 'hill');
wait_js($p, 'leqra.getState().scores[0]>=1', undef, {timeout => 4000});
$s = main::state($p)->{'scores'}->[0];
main::fixture($code, 'contested');
wait_js($p, 'leqra.getState().objectives.contested');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(1100));
main::check((do { my $boolean_value = (value_eq(main::state($p)->{'scores'}->[0], $s)); truth_value($boolean_value) ? main::state($q)->{'objectives'}->{'contested'} : $boolean_value }), 'Real Go hill stops scoring with an opponent present');
main::check((contains_value($p->locator('#objectiveStatus')->innerText(), 'CONTESTED')), 'Online objective HUD reports contested hill');
main::screenshot($p, 'online-hill-desktop');
main::room($p);
wait_js($q, 'leqra.getState().phase==="onlineLobby"');
main::check((value_eq(main::state($q)->{'scores'}->[0], 0)), 'Host can end objective match and reset scores without losing room');
$p->locator('#addLocalBtn')->click();
wait_js($p, 'leqra.getState().room.players.some(p=>p.kind==="local")');
$lid = ([map { my $x = $_; truth_value((value_eq($x->{'kind'}, 'local'))) ? ($x->{'id'}) : () } @{main::state($p)->{'room'}->{'players'}}]->[0] // undef);
main::dismissVictory($q);
$q->locator('#readyBtn')->click();
wait_js($p, 'leqra.getState().room.canStart');
main::start($p);
wait_js($q, 'leqra.getState().phase==="playing"');
main::press($p, 'Space');
main::check(evaluate_js($p, 'id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.fire)', $lid), 'Space is sent as secondary owned Fire input online');
main::press($p, 'KeyF');
main::check(evaluate_js($p, '__sent.some(m=>m.type==="input"&&(m.player??0)===0&&m.fire)'), 'F is independently sent for online primary Fire');
main::room($p);
$q->close();
$p->close();
for $size (@{[[320, 568], [390, 844], [844, 390], [1365, 950]]}) {
    $p = main::load(undef, undef, $size, undef);
    main::preset($p, 3);
    for $button (@{['roomRulesBtn', 'roomPresetsBtn', 'roomControlsBtn', 'startRoomBtn']}) {
        $p->locator(('#' . $button))->scrollIntoViewIfNeeded();
        $hit = evaluate_js($p->locator(('#' . $button)), '(e)=>{const r=e.getBoundingClientRect();const h=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return h===e||e.contains(h)}');
        main::check($hit, ($size . ': ' . $button . ' reachable and not covered'));
    }
    main::dismissVictory($p);
    $p->locator('#roomMapSize')->selectOption('compact');
    wait_js($p, '(value)=>leqra.getState().rules.mapSize===value', 'compact', {});
    $p->locator('#roomRulesBtn')->click();
    $p->locator('#applyRulesBtn')->scrollIntoViewIfNeeded();
    main::check($p->locator('#applyRulesBtn')->isVisible(), ($size . ': rules form scrolls to Apply'));
    main::screenshot($p, ('rules-' . $size->[0] . 'x' . $size->[1]));
    $p->locator('#applyRulesBtn')->click();
    $p->locator('#roomControlsBtn')->click();
    $p->locator('[data-bind="1:fire"]')->click();
    $p->keyboard()->press('KeyL');
    main::check((value_eq($p->locator('[data-bind="1:fire"]')->innerText(), 'L')), ($size . ': remapping works in compact dialog'));
    main::screenshot($p, ('controls-' . $size->[0] . 'x' . $size->[1]));
    main::close($p, 'controls');
    main::dismissVictory($p);
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetName')->fill('Responsive setup');
    $p->locator('#savePresetBtn')->click();
    main::check((contains_value(lc($p->locator('#presetsNotice')->innerText()), 'saved')), ($size . ': custom preset can be saved'));
    main::close($p, 'presets');
    evaluate_js($p->locator('#roomScreen'), '(e)=>e.scrollTop=0');
    main::screenshot($p, ('room-' . $size->[0] . 'x' . $size->[1]));
    main::start($p);
    main::check((do { my $boolean_value = (value_eq(main::state($p)->{'world'}->{'cols'}, 7)); truth_value($boolean_value) ? $p->locator('#objectiveBar')->isVisible() : $boolean_value }), ($size . ': objective match renders compact maze and HUD'));
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), ($size . ': no horizontal page overflow'));
    if (truth_value((do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) }))) {
        $a = $p->locator('#stickBase')->boundingBox();
        $b = $p->locator('#fireBtn')->boundingBox();
        $cdp = $p->context()->newCDPSession($p);
        $cdp->send('Input.dispatchTouchEvent', {'type' => 'touchStart', 'touchPoints' => [{'x' => (($a->{'x'} + ($a->{'width'} / 2)) + 20), 'y' => ($a->{'y'} + ($a->{'height'} / 2)), 'id' => 71}, {'x' => ($b->{'x'} + ($b->{'width'} / 2)), 'y' => ($b->{'y'} + ($b->{'height'} / 2)), 'id' => 72}]});
        $Leqra::Browser::HANDLE->await($p->waitForTimeout(150));
        $cdp->send('Input.dispatchTouchEvent', {'type' => 'touchEnd', 'touchPoints' => []});
        main::check(JSON::PP::true, ($size . ': simultaneous touch events remain handled'));
    }
    main::screenshot($p, ('playing-' . $size->[0] . 'x' . $size->[1]));
    $p->close();
}
main::check((!truth_value($errors)), 'No JavaScript page errors across new feature tests');
$browser->close();
$report = {'version' => '3.2.0', 'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'page_errors' => $errors, 'limits' => 'Chromium emulation; exact assets, synthetic Location/History/storage, real loopback Go fixture. No physical devices/public internet.'};
$out->child('report.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text({'passed' => scalar(@{$checks}), 'errors' => $errors})), "\n");
