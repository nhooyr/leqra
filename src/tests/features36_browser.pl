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

my ($ap, $args, $audit, $bad, $before, $browser, $c, $checks, $code, $contexts, $errors, $guest, $host, $i, $measurements, $mode, $n, $names, $out, $p, $pixels, $pw, $q, $r, $result, $root, $saved, $size, $spawnOK, $state1, $store, $t, $view, $web);
# v3.6: exact browser assets, local simulation and loopback Go snapshots.
# Uses Location/History/storage adapters; no shipped production debug endpoint.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:8878', 'output' => 'test-output/polish34', 'browser' => '/usr/bin/chromium', 'baseline' => undef); my $help; GetOptions('url=s' => \$args{'url'}, 'output=s' => \$args{'output'}, 'browser=s' => \$args{'browser'}, 'baseline=s' => \$args{'baseline'}, 'help|h' => \$help) or die 'Usage: perl features36_browser.pl --url --output --browser --baseline
'; if ($help) { print 'Usage: perl features36_browser.pl --url --output --browser --baseline
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
$measurements = [];
sub check {
    my ($v, $label) = @_;
    if (truth_value((!truth_value($v)))) {
        die json_text($label);
    }
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub fixture {
    my ($code, $action, $player) = @_;
    my ($r);
    $player //= 0;
    $r = request_ok(HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/features32'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'action' => $action, 'player' => $player}))));
    return decode_json($r->content);
}
sub state {
    my ($p) = @_;
    return evaluate_js($p, 'leqra.getState()');
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
$contexts = [];
sub load {
    my ($name, $size, $code, $watch, $storage, $source) = @_;
    my ($assets, $context, $html, $i, $js, $mobile, $p, $url, $w);
    $name //= 'HOST';
    $size //= [1365, 950];
    $code //= undef;
    $watch //= JSON::PP::false;
    $storage //= undef;
    $source //= undef;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $context = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $context);
    $p = $context->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->on('dialog', 'arguments[0].accept();');
    $w = (do { my $boolean_value = $source; truth_value($boolean_value) ? $boolean_value : $web });
    $assets = asset_directory($w);
    $html = replace_re('<link[^>]*>', '', $w->child('index.html')->slurp_utf8);
    $html = replace_re('<script src="[^"]+" defer></script>', '', $html);
    $html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
    $p->setContent($html);
    $url = ('http://game.test/tanks/?test=1' . (truth_value($code) ? ('&' . query_string({'room' => $code, %{(truth_value($watch) ? {'spectate' => 1} : {})}})) : ''));
    evaluate_js($p, '([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied=\'\';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({\'leqra.name\':name,\'leqra.muted\':\'1\'},storage||{});Object.defineProperty(window,\'localStorage\',{value:store(__store)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});}', [$url, (replace_text($args->{'url'}, 'http:', 'ws:') . '/ws'), $name, $storage]);
    $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
    $i = rindex($js, '})()');
    $js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    return $p;
}
sub closewin {
    my ($p) = @_;
    if (truth_value((do { my $boolean_value = $p->locator('#victoryDialog')->count(); truth_value($boolean_value) ? $p->locator('#victoryDialog')->isVisible() : $boolean_value }))) {
        $p->locator('#victoryCloseBtn')->click();
    }
}
sub preset {
    my ($p, $index) = @_;
    main::closewin($p);
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetSelect')->selectOption(('builtin:' . format_value($index)));
    $p->locator('#loadPresetBtn')->click();
    wait_js($p, '!document.querySelector("#presetsDialog").open');
}
sub start {
    my ($p) = @_;
    main::closewin($p);
    $p->locator('#startRoomBtn')->click();
    wait_js($p, 'leqra.getState().phase==="playing"', undef, {timeout => 9000});
}
sub room {
    my ($p) = @_;
    main::closewin($p);
    if (truth_value((value_eq(main::state($p)->{'mode'}, 'room')))) {
        evaluate_js($p, '__test.returnToRoom()');
        return undef;
    }
    $p->locator('#roomBtn')->click();
    $p->locator('#returnRoomBtn')->click();
    wait_js($p, '["menu","onlineLobby"].includes(leqra.getState().phase)');
}
sub rules {
    my ($p, $values) = @_;
    my ($control, $k, $n, $selected_mode, $selector, $setting, $v, $value);
    $values //= {};
    main::closewin($p);
    $selected_mode = splice(@{$values}, 'mode', 1);
    if (truth_value((defined($selected_mode)))) {
        $p->locator((('[data-room-mode="' . $selected_mode) . '"]'))->click();
        wait_js($p, '(mode)=>leqra.getState().rules.mode===mode', $selected_mode, {});
    }
    for my $item (@{[['teamMode', '#roomTeamMode'], ['mapSize', '#roomMapSize']]}) {
        my $tuple_43_6 = $item;
        my $setting = $tuple_43_6->[0];
        my $selector = $tuple_43_6->[1];
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
        my $tuple_50_6 = $item;
        my $k = $tuple_50_6->[0];
        my $v = $tuple_50_6->[1];
        my $n = $p->locator(('#rule-' . $k));
        if (truth_value((value_eq($k, 'friendlyFire')))) {
            $n->setChecked($v);
        } else {
            if (truth_value((contains_value(['teamMode', 'mapSize', 'pickupRate'], $k)))) {
                if (truth_value($n->isDisabled())) {
                    assert_ok((value_eq($n->inputValue(), format_value($v))), 'n.input_value()==str(v)');
                } else {
                    $n->selectOption(format_value($v));
                }
            } else {
                $n->fill(format_value($v));
            }
        }
    }
    $p->locator('#applyRulesBtn')->click();
    wait_js($p, '!document.querySelector("#rulesDialog").open');
}
sub box {
    my ($p) = @_;
    return evaluate_js($p, '()=>{const r=document.querySelector(\'#arenaWrap\').getBoundingClientRect(),u=document.querySelector(\'.underbar\').getBoundingClientRect();return {width:r.width,height:r.height,x:r.x,y:r.y,hud:u.height,canvasW:document.querySelector(\'#arena\').width,canvasH:document.querySelector(\'#arena\').height};}');
}
sub freeze {
    my ($p) = @_;
    evaluate_js($p, '()=>{__test.setPhase(\'paused\');__test.clearBullets();for(const t of __test.tanks){t.power=null;t.powerTime=0;t.speedTime=0;t.shield=0;t.alive=true;t.invulnerable=0;}__test.updateHUD(true);}');
    $Leqra::Browser::HANDLE->await($p->waitForTimeout(80));
}
eval {
    $names = ['Aurora 🌟', '<b>Fire</b>', 'Tidal & Co', 'Violet Guard'];
    for $size (@{[[1365, 950], [320, 568], [844, 390]]}) {
        $p = main::load(undef, $size, undef, undef, undef, undef);
        $r = main::state($p);
        main::check((do { my $boolean_value = (value_eq($r->{'rules'}->{'teamMode'}, 'ffa')); truth_value($boolean_value) ? (value_eq($r->{'rules'}->{'mapSize'}, 'large')) : $boolean_value }), ('Default FFA / 12x10 ' . format_value($size)));
        main::check((do { my $boolean_value = (value_eq(scalar(@{$r->{'room'}->{'players'}}), 4)); truth_value($boolean_value) ? (value_eq(sum(@{[map { my $t = $_; (do { my $boolean_value = (value_eq($t->{'kind'}, 'bot')); truth_value($boolean_value) ? (value_eq($t->{'difficulty'}, 'normal')) : $boolean_value }) } @{$r->{'room'}->{'players'}}]}), 3)) : $boolean_value }), ('Default three Normal bots ' . format_value($size)));
        main::check((do { my $boolean_value = !scalar(grep { my $t = $_; !((value_eq($t->{'team'}, 0))) } @{$r->{'room'}->{'players'}}); truth_value($boolean_value) ? (value_eq(evaluate_js($p, '__sockets.length'), 0)) : $boolean_value }), ('Default four independent opponents, no network connection ' . format_value($size)));
        $p->locator('#addLocalBtn')->click();
        while (truth_value(((scalar(@{main::state($p)->{'room'}->{'players'}}) < 8)))) {
            $p->locator('#addBotBtn')->click();
        }
        main::check(!scalar(grep { my $t = $_; !((value_eq($t->{'team'}, 0))) } @{main::state($p)->{'room'}->{'players'}}), ('Add bot/P2 never groups FFA tanks ' . format_value($size)));
        main::rules($p, {'teamMode' => 'teams'});
        main::check((value_eq(main::state($p)->{'rules'}->{'teamNames'}, $names)), ('Four custom names accepted ' . format_value($size)));
        main::check((value_eq(evaluate_js($p->locator('[data-team]')->first(), '(e)=>[...e.options].map(o=>o.value)'), ['1', '2', '3', '4'])), ('Teams dropdown has exactly four choices ' . format_value($size)));
        main::check((do { my $boolean_value = (value_eq(evaluate_js($p->locator('[data-team]')->first(), '(e)=>e.options[1].textContent'), '<b>Fire</b>, T2')); truth_value($boolean_value) ? (!truth_value($p->locator('[data-team] b')->count())) : $boolean_value }), ('Team names are literal text, not HTML ' . format_value($size)));
        main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow with team names ' . format_value($size)));
        $p->locator('#roomRulesBtn')->click();
        $p->screenshot({path => format_value($out->child(('team-settings-' . $size->[0] . '.png')))});
        $p->locator('[data-close-dialog="rulesDialog"]')->click();
        main::rules($p, {'mode' => 'ctf', 'timeLimit' => 600, 'scoreTarget' => 20});
        main::start($p);
        main::freeze($p);
        $spawnOK = evaluate_js($p, '()=>{const T=__test,o=T.localObjectives;for(let k=0;k<12;k++)for(const t of T.tanks){t.alive=false;T.respawnLocalTank(t);const f=o.flags.find(f=>f.team===t.team),w=leqra.getState().world;if(Math.floor(t.x/84)===Math.floor(f.homeX/84)&&Math.floor(t.y/84)===Math.floor(f.homeY/84)||Math.hypot(t.x-f.x,t.y-f.y)<t.r+32)return false;}return true}');
        main::check($spawnOK, ('Eight tanks never spawn in their flag cell ' . format_value($size)));
        $pixels = evaluate_js($p, '()=>{const T=__test,o=T.localObjectives,f=o.flags[0],t=T.tanks.find(t=>t.team===f.team),v=T.view,w=leqra.getState().world,z=Math.max(1.35,1/v.scale),clamp=(x,a,b)=>Math.max(a,Math.min(b,x));t.x=clamp(f.x,40*z,w.width-40*z);t.y=clamp(f.y-12*z,26*z,w.height-36*z);t.angle=0;t.recoil=0;t.shield=t.speedTime=t.invulnerable=0;T.clearBullets();const canvas=document.querySelector(\'#arena\'),c=canvas.getContext(\'2d\'),d=canvas.width/v.cssW;const crop=()=>Array.from(c.getImageData(Math.round((v.offsetX+(t.x-10)*v.scale)*d),Math.round((v.offsetY+(t.y-5)*v.scale)*d),Math.max(1,Math.floor(18*v.scale*d)),Math.max(1,Math.floor(10*v.scale*d))).data);T.render();const a=crop(),flags=o.flags;o.flags=[];T.render();const b=crop();o.flags=flags;T.render();return a.every((v,i)=>v===b[i]);}');
        main::check($pixels, ('Flag cannot cover ally hull: pixel comparison ' . format_value($size)));
        $before = main::box($p);
        evaluate_js($p, '()=>{for(const t of __test.tanks)if(t.human){__test.grantPower(t,\'speed\');t.shield=10;}__test.updateHUD(true)}');
        $Leqra::Browser::HANDLE->await($p->waitForTimeout(70));
        main::check((value_eq(main::box($p), $before)), ('Buffs retain stable maze dimensions ' . format_value($size)));
        main::check($p->locator('#pilotLoadout2')->isVisible(), ('Player 2 retains own ammo ' . format_value($size)));
        $p->screenshot({path => format_value($out->child(('flags-behind-tanks-' . $size->[0] . '.png')))});
        main::room($p);
        $p->locator('#roomPresetsBtn')->click();
        $p->locator('#presetName')->fill('Named teams 36');
        $p->locator('#savePresetBtn')->click();
        $store = evaluate_js($p, '__store');
        $saved = decode_json($store->{'leqra.presets.v1'})->{'items'}->[0];
        main::check((value_eq($saved->{'rules'}->{'teamNames'}, $names)), ('Preset includes all four names ' . format_value($size)));
        $p->close();
    }
    $p = main::load(undef, undef, undef, undef, $store, undef);
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetSelect')->selectOption('saved:0');
    $p->locator('#loadPresetBtn')->click();
    main::check((value_eq(main::state($p)->{'rules'}->{'teamNames'}, $names)), 'Reloaded browser preset restores names');
    $result = evaluate_js($p, '()=>{const T=__test,r=T.currentRules(),old={name:\'Legacy\',rules:{...r,teamMode:\'teams\'},roster:[{kind:\'human\',name:\'P1\',team:0},{kind:\'bot\',name:\'BOT\',difficulty:\'normal\',team:0}]};delete old.rules.teamNames;const p=T.validatePreset(old);return p.roster.map(p=>p.team).join(\',\')===\'1,2\'&&p.rules.teamNames.join(\',\')===\'Team 1,Team 2,Team 3,Team 4\';}');
    main::check($result, 'Legacy Independent presets migrate into numbered teams');
    $bad = evaluate_js($p, '()=>{let bad=[[],[\'A\',\'B\'],[\'\\n\',\'B\',\'C\',\'D\'],[\'\\u200b\',\'B\',\'C\',\'D\'],[\'x\'.repeat(25),\'B\',\'C\',\'D\']];return bad.every(teamNames=>{try{__test.validateRoomRules({...__test.currentRules(),teamNames});return false}catch(_){return true}});}');
    main::check($bad, 'Browser validates count, visibility, length and controls');
    main::check(evaluate_js($p, '()=>{const r=__test.validateRoomRules({...__test.currentRules(),teamNames:[\'💥\'.repeat(24),\' B \',\'C\',\'D\']});return r.teamNames[0].length===48&&r.teamNames[1]===\'B\';}'), '24 emoji codepoints and outer-space trim agree with server');
    $p->close();
    for $mode (@{['ctf', 'koth']}) {
        $p = main::load();
        main::preset($p, (truth_value((value_eq($mode, 'ctf'))) ? 3 : 4));
        main::start($p);
        main::freeze($p);
        $audit = evaluate_js($p, 'mode=>{const T=__test,s=leqra.getState(),w=s.world;T.setWorld({...w,walls:[]});T.clearBullets();T.setPhase(\'playing\');for(const t of T.tanks){t.human=true;t.cooldown=999;t.invulnerable=0;t.speedTime=0;t.x=200+t.id*100;t.y=250;}const o=T.localObjectives,a=T.tanks[0];if(mode===\'ctf\'){const f=o.flags.find(f=>f.team===a.team),enemy=o.flags.find(f=>f.team!==a.team);a.x=f.homeX;a.y=f.homeY;Object.assign(enemy,{carrier:a.id,home:false,x:a.x,y:a.y});T.setClock(0);}else{a.x=o.hillX;a.y=o.hillY;o.owner=-a.id-1;o.hold=.996;T.setClock(.001);}T.update(1/120);T.setPhase(\'paused\');return {scores:leqra.getState().scores,sd:T.localObjectives.suddenDeath};}', $mode);
        main::check((do { my $boolean_value = (!truth_value(scalar(grep { $_ } @{$audit->{'scores'}}))); truth_value($boolean_value) ? $audit->{'sd'} : $boolean_value }), (('No post-deadline ' . $mode) . ' point; tie enters sudden death'));
        $p->close();
    }
    $p = main::load();
    main::preset($p, 4);
    main::start($p);
    main::freeze($p);
    $audit = evaluate_js($p, '()=>{const T=__test,w=leqra.getState().world;T.setWorld({...w,walls:[]});T.setPhase(\'playing\');T.setClock(100);for(const t of T.tanks){t.human=true;t.cooldown=999;t.x=300+t.id*100;t.y=250;}T.tanks[1].x=T.tanks[0].x;T.update(1/120);T.setPhase(\'paused\');return Math.hypot(T.tanks[0].x-T.tanks[1].x,T.tanks[0].y-T.tanks[1].y)>=33.99;}');
    main::check($audit, 'Coincident local tanks separate instead of remaining stacked');
    $audit = evaluate_js($p, '()=>{const T=__test;t=T.tanks[0];T.setPhase(\'matchOver\');const before=JSON.stringify(leqra.getState().scores);T.addObjectivePoint(t);return before===JSON.stringify(leqra.getState().scores)}');
    main::check($audit, 'Objective points remain frozen after match completion');
    $p->close();
    $p = main::load();
    main::preset($p, 3);
    for $size (@{['compact', 'standard', 'large', 'huge']}) {
        $result = evaluate_js($p, 'size=>{const T=__test;T.setLocalRules({...T.currentRules(),mapSize:size});for(let seed=0;seed<10;seed++){T.startRound();const o=T.localObjectives;for(const t of T.tanks){const f=o.flags.find(f=>f.team===t.team);if(Math.floor(t.x/84)===Math.floor(f.homeX/84)&&Math.floor(t.y/84)===Math.floor(f.homeY/84))return false;}}T.setPhase(\'menu\');return true}', $size);
        main::check($result, ('Seeded CTF start placement ' . $size));
    }
    $p->close();
    $host = main::load();
    $code = ('Teams v36 🌟 ' . format_value(int(time() * 1e9)));
    $host->locator('#addLocalBtn')->click();
    while (truth_value(((scalar(@{main::state($host)->{'room'}->{'players'}}) < 7)))) {
        $host->locator('#addBotBtn')->click();
    }
    main::rules($host, {'teamMode' => 'teams', 'mode' => 'ctf', 'scoreTarget' => 2, 'timeLimit' => 600});
    $host->locator('#localRoomName')->fill($code);
    $host->locator('#copyInviteBtn')->click();
    wait_js($host, 'leqra.getState().online.connected');
    main::check((value_eq(main::state($host)->{'rules'}->{'teamNames'}, $names)), 'Publishing transfers team names to Go');
    $guest = main::load('GUEST', undef, $code, undef, undef, undef);
    wait_js($guest, 'leqra.getState().online.connected');
    main::check((value_eq(main::state($guest)->{'online'}->{'id'}, 7)), 'Guest takes eighth tank');
    $view = main::load('VIEWER', [320, 568], $code, undef, undef, undef);
    wait_js($view, 'leqra.getState().online.connected');
    main::check(main::state($view)->{'online'}->{'spectating'}, 'Full eight-tank room still welcomes spectator');
    $guest->locator('#roomRulesBtn')->click();
    main::check($guest->locator('#rule-teamName1')->isDisabled(), 'Guest cannot edit team-name fields');
    $guest->locator('[data-close-dialog="rulesDialog"]')->click();
    main::check((contains_value($guest->locator('#roomRoster')->innerText(), $names->[0])), 'Custom team name visible to guest');
    $guest->locator('#readyBtn')->click();
    wait_js($host, 'leqra.getState().room.canStart');
    main::start($host);
    wait_js($view, 'leqra.getState().phase==="playing"');
    $state1 = main::state($host);
    main::check((value_eq(scalar(@{$state1->{'tanks'}}), 8)), 'Eight authoritative CTF tanks');
    main::check(evaluate_js($host, '()=>{const s=__messages.find(m=>m.type===\'state\'&&m.phase===\'countdown\'&&m.objectives?.flags?.length);return s.tanks.every(t=>{const f=s.objectives.flags.find(f=>f.team===t.team);return Math.floor(t.x/84)!==Math.floor(f.homeX/84)||Math.floor(t.y/84)!==Math.floor(f.homeY/84);});}'), 'Online initial tank spawns avoid flags');
    for $i (@{[0 .. 2 - 1]}) {
        main::fixture($code, 'capture', 0);
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(180));
    }
    wait_js($host, 'document.querySelector("#victoryDialog").open');
    wait_js($view, 'document.querySelector("#victoryDialog").open');
    main::check((contains_value($host->locator('#victoryTitle')->innerText(), $names->[0])), 'Winning popup uses custom team name');
    main::check((contains_value($view->locator('#victoryTitle')->innerText(), $names->[0])), 'Spectators see custom winning team name');
    main::check((!truth_value($view->locator('#victoryDialog b')->count())), 'Markup team name is not inserted as HTML');
    $view->screenshot({path => format_value($out->child('online-named-victory-320.png'))});
    for $q (@{[$host, $guest, $view]}) {
        $q->close();
    }
    $p = main::load();
    main::start($p);
    main::freeze($p);
    main::check(evaluate_js($p, '()=>{const T=__test,t=T.tanks[1];for(let i=0;i<260;i++){const copy={...t,name:\'CACHE \'+i,color:\'#\'+(0x100000+i*577).toString(16).padStart(6,\'0\'),track:i*2};T.drawTank(copy);}return T.renderStats.hullEntries<=96&&T.renderStats.labelEntries<=192;}'), 'Sprite and label caches stay bounded with changing colors/names');
    $p->close();
    main::check((!truth_value($errors)), 'No JavaScript exceptions across local/online trials');
    $out->child('results.json')->spew_utf8(json_text({'version' => '3.7.1', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors}, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
if ($@) {
    for my $item (@{[map { [$_, $contexts->[$_]] } 0 .. $#{$contexts}]}) {
        my $tuple_131_6 = $item;
        my $i = $tuple_131_6->[0];
        my $c = $tuple_131_6->[1];
        for my $p (@{$c->{'pages'}}) {
            eval {
                $p->screenshot({path => format_value($out->child(('failure-' . $i . '.png')))});
            1;
            };
            if ($@) {
            }
        }
    }
    $out->child('failure.json')->spew_utf8(json_text({'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors}, 1));
    die undef;
}
$browser->close();
