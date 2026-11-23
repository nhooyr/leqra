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

my ($a, $ap, $args, $assets, $browser, $checks, $code, $contexts, $control, $copied, $empty, $errors, $fallback, $h, $hit, $host, $local, $lp, $nw, $oldid, $out, $p, $p2, $page, $pw, $report, $restored, $root, $saved, $sent, $seq_before, $session, $size, $t, $token, $v, $watcher, $web);
# v3.3 spectator roles, links, swaps, persistence and mobile browser checks.
# Uses shipped assets with Location/History/storage adapters because navigation is
# blocked in the execution environment. The fixture server is opt-in and loopback-only.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:8878', 'browser' => '/usr/bin/chromium', 'output' => 'test-output/spectators33'); my $help; GetOptions('url=s' => \$args{'url'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl spectators_browser.pl --url --browser --output
'; if ($help) { print 'Usage: perl spectators_browser.pl --url --browser --output
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
    my ($name, $code, $size, $storage, $watch, $session) = @_;
    my ($ctx, $html, $i, $js, $mobile, $p, $url);
    $name //= 'HOST';
    $code //= undef;
    $size //= [1365, 950];
    $storage //= undef;
    $watch //= JSON::PP::false;
    $session //= undef;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $ctx = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $ctx);
    $p = $ctx->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->on('dialog', 'arguments[0].accept();');
    $html = replace_text(replace_text(replace_text(replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8), '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', ''), '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
    $p->setContent($html);
    $url = (('http://game.test/tanks/?test=1' . (truth_value($code) ? ('&' . query_string({'room' => $code})) : '')) . (truth_value($watch) ? '&spectate=1' : ''));
    evaluate_js($p, '([url,ws,name,storage,session])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied=\'\';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=(data)=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({\'leqra.name\':name,\'leqra.muted\':\'1\'},storage||{});Object.defineProperty(window,\'localStorage\',{value:store(__store)});window.__session=Object.assign({},session||{});Object.defineProperty(window,\'sessionStorage\',{value:store(__session)});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});}', [$url, (replace_text($args->{'url'}, 'http:', 'ws:') . '/ws'), $name, $storage, $session]);
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
sub conn {
    my ($p) = @_;
    wait_js($p, 'leqra.getState().online?.connected', undef, {timeout => 9000});
}
sub wire {
    my ($p, $m) = @_;
    evaluate_js($p, 'm=>__sockets.at(-1).send(JSON.stringify(m))', $m);
}
sub watchJoin {
    my ($p, $name) = @_;
    $p->locator('#pilotName')->fill($name);
    $p->locator('#joinRoomBtn')->click();
    main::conn($p);
    wait_js($p, 'leqra.getState().online.spectating');
}
sub role {
    my ($p, $watching) = @_;
    evaluate_js($p, 'v=>{const s=leqra.getState();const r=s.room;const id=s.online?.id??r.host;__test.setPlayerSpectating([...r.players,...r.spectators].find(x=>x.id===id),v)}', $watching);
    wait_js($p, 'v=>!!leqra.getState().online?.spectating===v', $watching, {});
}
sub spectator {
    my ($p, $name) = @_;
    my ($x);
    return ([map { my $x = $_; truth_value((value_eq($x->{'name'}, $name))) ? ($x) : () } @{main::state($p)->{'room'}->{'spectators'}}]->[0] // undef);
}
sub member {
    my ($p, $name) = @_;
    my ($x);
    return ([map { my $x = $_; truth_value((value_eq($x->{'name'}, $name))) ? ($x) : () } @{(main::state($p)->{'room'}->{'players'} + main::state($p)->{'room'}->{'spectators'})}]->[0] // undef);
}
sub membercount {
    my ($p, $n) = @_;
    wait_js($p, 'n=>leqra.getState().room.spectators.length===n', $n, {});
}
sub openGallery {
    my ($p) = @_;
    if (truth_value((!truth_value(evaluate_js($p->locator('#spectatorsDialog'), '(e)=>e.open'))))) {
        $p->locator('#spectatorsBtn')->click();
    }
}
sub closeGallery {
    my ($p) = @_;
    if (truth_value(evaluate_js($p->locator('#spectatorsDialog'), '(e)=>e.open'))) {
        $p->locator('#closeSpectatorsBtn')->click();
    }
}
sub swap {
    my ($p, $viewer, $active) = @_;
    my ($a, $v);
    main::openGallery($p);
    $v = main::spectator($p, $viewer);
    $a = main::member($p, $active);
    $p->locator((('#spectatorList [data-swap-viewer="' . format_value($v->{'id'})) . '"]'))->click();
    $p->locator('#swapTarget')->selectOption(((format_value($a->{'id'}) . ':') . format_value($a->{'member'})));
    $p->locator('#confirmSwapBtn')->click();
    wait_js($p, '!document.querySelector("#swapDialog").open');
    main::closeGallery($p);
}
sub screenshot {
    my ($p, $n) = @_;
    $p->screenshot({path => format_value($out->child(($n . '.png')))});
}
$local = main::load('LOCAL HOST');
$local->locator('#addLocalBtn')->click();
$local->locator('#toggleSpectateBtn')->click();
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($local)->{'room'}->{'players'}}), 3)); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($local)->{'room'}->{'spectators'}}), 1)) : $boolean_value }), 'Local host can spectate without occupying a tank slot');
main::check((do { my $boolean_value = ((main::state($local)->{'room'}->{'host'} >= 4)); truth_value($boolean_value) ? $local->locator('#startRoomBtn')->isEnabled() : $boolean_value }), 'Spectating local host keeps Start and team controls');
main::start($local);
main::lane($local);
main::check((!truth_value(scalar(grep { my $t = $_; (value_eq($t->{'id'}, main::state($local)->{'room'}->{'host'})) } @{main::state($local)->{'tanks'}}))), 'Local watching host has no tank in simulation');
main::check((truth_value($local->locator('#pilotLoadout1')->count()) ? $local->locator('#pilotLoadout1')->isHidden() : $local->locator('#spectatorBanner')->isVisible()), 'Watching replaces primary ammo with spectator banner');
main::check($local->locator('#pilotLoadout2')->isVisible(), 'Active local P2 keeps their ammo while P1 watches');
evaluate_js($local, '()=>{const p=__test.tanks.find(t=>t.human);p.cooldown=0;__test.grantPower(p,\'grenade\');p.charges=1;}');
main::press($local, 'Space');
main::check(evaluate_js($local, '__test.bullets.some(b=>b.kind==="grenade"&&b.owner===3)'), 'Local P2 fires independently while primary spectates');
main::room($local);
main::start($local);
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($local)->{'room'}->{'spectators'}}), 1)); truth_value($boolean_value) ? (!truth_value(scalar(grep { my $t = $_; (($t->{'id'} >= 4)) } @{main::state($local)->{'tanks'}}))) : $boolean_value }), 'Starting another local match retains spectator role');
main::room($local);
$local->locator('#localRoomName')->fill(('Local spectators ' . format_value(int(time() * 1e9))));
$local->locator('#copyInviteBtn')->click();
main::conn($local);
main::check((do { my $boolean_value = main::state($local)->{'online'}->{'spectating'}; truth_value($boolean_value) ? do { my $boolean_value = (value_eq(scalar(@{main::state($local)->{'room'}->{'spectators'}}), 1)); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($local)->{'room'}->{'players'}}), 3)) : $boolean_value } : $boolean_value }), 'Sharing imports watching host with active local P2 and bots');
main::check((value_eq(([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p) : () } @{main::state($local)->{'room'}->{'players'}}]->[0] // undef)->{'owner'}, main::state($local)->{'online'}->{'id'})), 'Shared P2 remains owned by watching controller');
$lp = ([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p) : () } @{main::state($local)->{'room'}->{'players'}}]->[0] // undef);
main::swap($local, 'LOCAL HOST', $lp->{'name'});
wait_js($local, '!leqra.getState().online.spectating');
main::swap($local, $lp->{'name'}, 'LOCAL HOST');
wait_js($local, 'leqra.getState().online.spectating');
$lp = ([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p) : () } @{main::state($local)->{'room'}->{'players'}}]->[0] // undef);
main::check((value_eq($lp->{'owner'}, main::state($local)->{'online'}->{'id'})), 'Swapping own primary with own local P2 preserves keyboard ownership');
main::start($local);
main::press($local, 'Space');
wait_js($local, 'leqra.getState().online.serverTick>3');
main::check((do { my $boolean_value = evaluate_js($local, 'id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.fire)', $lp->{'id'}); truth_value($boolean_value) ? (!truth_value(evaluate_js($local, '__messages.some(m=>m.type==="error"&&m.code==="not_owned")'))) : $boolean_value }), 'Real server accepts P2 Fire after two self-local swaps');
main::room($local);
$local->locator('#leaveRoomBtn')->click();
$local->close();
$host = main::load('HOST');
$host->locator('#addLocalBtn')->click();
$code = ('Watch & play 💥 ' . format_value(int(time() * 1e9)));
$host->locator('#localRoomName')->fill($code);
$host->locator('#copyInviteBtn')->click();
main::conn($host);
$host->locator('#copySpectateBtn')->click();
$copied = evaluate_js($host, '__copied');
main::check((do { my $boolean_value = (contains_value($copied, 'spectate=1')); truth_value($boolean_value) ? (value_eq(evaluate_js($host, 'new URL(__copied).searchParams.get("room")'), $code)) : $boolean_value }), 'Spectator share link encodes full Unicode/punctuation room name');
main::check((do { my $boolean_value = (!(contains_value($copied, 'token'))); truth_value($boolean_value) ? (!(contains_value($copied, evaluate_js($host, '__test.online.token')))) : $boolean_value }), 'Public watch link contains no private reconnect credential');
evaluate_js($host, '__location.hostname="localhost"');
$host->locator('#copySpectateBtn')->click();
main::check((do { my $boolean_value = evaluate_js($host, 'new URL(__copied).searchParams.get("spectate")==="1"'); truth_value($boolean_value) ? (contains_value(lc($host->locator('#roomStatus')->innerText()), 'localhost only')) : $boolean_value }), 'Localhost spectator copy remains a watch link with cross-device warning');
evaluate_js($host, '__location.hostname="game.test"');
$watcher = main::load('SAVED NAME', $code, undef, undef, JSON::PP::true, undef);
main::check((do { my $boolean_value = evaluate_js($watcher->locator('#joinDialog'), '(e)=>e.open'); truth_value($boolean_value) ? (value_eq($watcher->locator('#joinTitle')->innerText(), 'Watch this room.')) : $boolean_value }), 'Watch link opens callsign-first dialog');
main::check((do { my $boolean_value = evaluate_js($watcher, '__sockets.length===0'); truth_value($boolean_value) ? (!truth_value(main::state($watcher)->{'online'})) : $boolean_value }), 'Watch link does not connect or occupy membership before confirmation');
$watcher->locator('#pilotName')->fill('');
$watcher->locator('#joinRoomBtn')->click();
main::check((do { my $boolean_value = (contains_value(lc($watcher->locator('#netStatus')->innerText()), 'callsign')); truth_value($boolean_value) ? evaluate_js($watcher, '__sockets.length===0') : $boolean_value }), 'Empty callsign cannot enter spectator link');
main::watchJoin($watcher, 'VIEWER');
main::membercount($host, 1);
main::check((do { my $boolean_value = ((main::state($watcher)->{'online'}->{'id'} >= 4)); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($watcher)->{'room'}->{'players'}}), 4)) : $boolean_value }), 'Explicit viewer is outside all four tank slots');
main::check((do { my $boolean_value = $watcher->locator('#readyBtn')->isHidden(); truth_value($boolean_value) ? $watcher->locator('#toggleSpectateBtn')->isDisabled() : $boolean_value }), 'Spectator has no ready vote and cannot join full arena');
$fallback = main::load('OVERFLOW', $code);
main::conn($fallback);
wait_js($fallback, 'leqra.getState().online.spectating');
main::membercount($host, 2);
main::check(evaluate_js($fallback, '__messages.some(m=>m.type==="welcome"&&m.full&&m.spectating)'), 'Normal invite to full room automatically enters as spectator');
main::check((!truth_value(evaluate_js($fallback, '__messages.some(m=>m.type==="error"&&m.code==="room_full")'))), 'Full arena does not decline visitor with room-full error');
for $page (@{[$host, $watcher, $fallback]}) {
    main::membercount($page, 2);
    main::openGallery($page);
    main::check((do { my $boolean_value = (value_eq($page->locator('#spectatorList')->innerText()->count('VIEWER'), 1)); truth_value($boolean_value) ? (contains_value($page->locator('#spectatorList')->innerText(), 'OVERFLOW')) : $boolean_value }), 'Every room member can inspect spectator names');
    if (truth_value((!value_eq($page, $host)))) {
        main::check((do { my $boolean_value = (value_eq($page->locator('#spectatorList [data-swap-viewer]')->count(), 0)); truth_value($boolean_value) ? (value_eq($page->locator('#spectatorList [data-kick-target]')->count(), 0)) : $boolean_value }), 'Spectator guest has no host moderation controls');
    }
    main::closeGallery($page);
}
main::check($host->locator('#startRoomBtn')->isEnabled(), 'Host can start full lineup without spectator readiness');
main::start($host);
wait_js($watcher, 'leqra.getState().phase==="playing"');
wait_js($fallback, 'leqra.getState().phase==="playing"');
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($watcher)->{'tanks'}}), 4)); truth_value($boolean_value) ? (!truth_value(scalar(grep { my $t = $_; (value_eq($t->{'id'}, main::state($watcher)->{'online'}->{'id'})) } @{main::state($watcher)->{'tanks'}}))) : $boolean_value }), 'Viewer sees live four-tank world but owns no tank');
main::check((do { my $boolean_value = $watcher->locator('#overlay')->isHidden(); truth_value($boolean_value) ? $watcher->locator('#spectatorBanner')->isVisible() : $boolean_value }), 'Watcher automatically sees arena rather than blocking room overlay');
$t = main::state($watcher)->{'online'}->{'serverTick'};
$Leqra::Browser::HANDLE->await($watcher->waitForTimeout(160));
main::check(((main::state($watcher)->{'online'}->{'serverTick'} > $t)), 'Viewer receives continuing authoritative game snapshots');
$sent = evaluate_js($watcher, '__sent.length');
main::press($watcher, 'KeyF');
main::press($watcher, 'Space');
main::press($watcher, 'KeyW');
main::check((!truth_value(evaluate_js($watcher, 'n=>__sent.slice(n).some(m=>m.type==="input")', $sent))), 'Spectator keyboard cannot send gameplay controls');
$oldid = main::state($watcher)->{'online'}->{'id'};
$token = evaluate_js($watcher, '__test.online.token');
evaluate_js($watcher, '__sockets.at(-1).close(4000,"test reconnect")');
wait_js($watcher, '__messages.filter(m=>m.type==="welcome").length>=2', undef, {timeout => 9000});
main::check((do { my $boolean_value = main::state($watcher)->{'online'}->{'spectating'}; truth_value($boolean_value) ? do { my $boolean_value = (value_eq(main::state($watcher)->{'online'}->{'id'}, $oldid)); truth_value($boolean_value) ? (value_eq(evaluate_js($watcher, '__test.online.token'), $token)) : $boolean_value } : $boolean_value }), 'Automatic reconnect preserves watcher role, identity and session');
main::openGallery($host);
$v = main::spectator($host, 'OVERFLOW');
$host->locator((('#spectatorList [data-kick-target="' . format_value($v->{'id'})) . '"]'))->click();
$host->locator('#confirmKickBtn')->click();
wait_js($host, '!document.querySelector("#kickDialog").open');
main::closeGallery($host);
wait_js($fallback, '!leqra.getState().online?.connected');
main::membercount($host, 1);
main::check((do { my $boolean_value = evaluate_js($fallback, '!__session["leqra.session"]'); truth_value($boolean_value) ? evaluate_js($fallback, '__messages.some(m=>m.type==="kicked")') : $boolean_value }), 'Host kicking spectator clears reconnect credential and explains removal');
$nw = evaluate_js($fallback, '__messages.filter(m=>m.type==="welcome").length');
$Leqra::Browser::HANDLE->await($fallback->waitForTimeout(900));
main::check((value_eq(evaluate_js($fallback, '__messages.filter(m=>m.type==="welcome").length'), $nw)), 'Kicked spectator does not automatically rejoin');
$fallback->close();
$p2 = ([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p) : () } @{main::state($host)->{'room'}->{'players'}}]->[0] // undef);
$seq_before = evaluate_js($host, '__test.online.seq');
main::swap($host, 'VIEWER', $p2->{'name'});
wait_js($watcher, '!leqra.getState().online.spectating');
main::check((do { my $boolean_value = (value_eq(main::state($watcher)->{'online'}->{'id'}, $p2->{'id'})); truth_value($boolean_value) ? main::member($host, $p2->{'name'})->{'spectating'} : $boolean_value }), 'Host swap makes viewer active and former P2 a spectator');
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'room'}->{'host'}, 0)); truth_value($boolean_value) ? (value_eq(main::member($host, 'VIEWER')->{'team'}, $p2->{'team'})) : $boolean_value }), 'Swap keeps host authority and transfers selected seat team');
main::check((value_eq(evaluate_js($watcher, '__test.online.token'), $token)), 'Swap does not replace viewer reconnect identity');
main::check((!truth_value(([map { my $t = $_; truth_value((value_eq($t->{'id'}, $p2->{'id'}))) ? ($t) : () } @{main::state($watcher)->{'tanks'}}]->[0] // undef)->{'alive'})), 'Mid-round incoming elimination player does not receive an extra tank life');
main::check($host->locator('#pilotLoadout2')->isHidden(), 'Watching local P2 no longer shows a playable ammo panel');
main::check(((evaluate_js($host, '__test.online.seq') >= $seq_before)), 'Role notifications preserve input sequence chronology for unaffected pilots');
main::role($watcher, JSON::PP::true);
main::check((value_eq(scalar(@{main::state($watcher)->{'room'}->{'players'}}), 3)), 'Active guest can voluntarily move to spectators');
main::role($watcher, JSON::PP::false);
main::check((value_eq(scalar(@{main::state($watcher)->{'room'}->{'players'}}), 4)), 'Spectator can return to an available tank seat');
wait_js($watcher, 'leqra.getState().tanks.some(t=>t.id===leqra.getState().online.id)');
main::check((!truth_value(([map { my $t = $_; truth_value((value_eq($t->{'id'}, main::state($watcher)->{'online'}->{'id'}))) ? ($t) : () } @{main::state($watcher)->{'tanks'}}]->[0] // undef)->{'alive'})), 'Role toggling cannot bypass elimination death');
main::role($watcher, JSON::PP::true);
main::room($host);
wait_js($watcher, 'leqra.getState().phase==="onlineLobby"');
main::check(main::state($watcher)->{'online'}->{'spectating'}, 'Host End match keeps spectators watching');
main::start($host);
wait_js($watcher, 'leqra.getState().phase==="playing"');
main::check((do { my $boolean_value = main::state($watcher)->{'online'}->{'spectating'}; truth_value($boolean_value) ? (value_eq(scalar(@{main::state($watcher)->{'room'}->{'spectators'}}), 2)) : $boolean_value }), 'New online match does not auto-promote previous spectators');
main::swap($host, 'VIEWER', 'HOST');
wait_js($watcher, '!leqra.getState().online.spectating');
wait_js($host, 'leqra.getState().online.spectating');
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'room'}->{'host'}, main::state($host)->{'online'}->{'id'})); truth_value($boolean_value) ? $host->locator('#spectatorBanner')->isVisible() : $boolean_value }), 'Host retains authority after moving themselves to spectators');
main::check((!value_eq(main::state($watcher)->{'room'}->{'host'}, main::state($watcher)->{'online'}->{'id'})), 'Taking host former tank does not transfer host privileges');
main::room($host);
wait_js($watcher, 'leqra.getState().phase==="onlineLobby"');
main::dismissVictory($watcher);
$watcher->locator('#readyBtn')->click();
wait_js($host, 'leqra.getState().room.canStart');
main::start($host);
main::check(main::state($host)->{'online'}->{'spectating'}, 'Spectating host can start subsequent match');
$oldid = main::state($host)->{'online'}->{'id'};
$session = evaluate_js($host, '__session');
$saved = evaluate_js($host, '__store');
$host->context()->close();
$Leqra::Browser::HANDLE->await($watcher->waitForTimeout(100));
$restored = main::load('HOST', $code, undef, $saved, JSON::PP::true, $session);
main::check(evaluate_js($restored, '__sockets.length===0'), 'Reloaded watch link still requires callsign confirmation before resume');
main::watchJoin($restored, 'HOST');
main::check((do { my $boolean_value = (value_eq(main::state($restored)->{'online'}->{'id'}, $oldid)); truth_value($boolean_value) ? evaluate_js($restored, '__messages.some(m=>m.type==="welcome"&&m.resumed)') : $boolean_value }), 'Confirmed watch refresh resumes existing spectator identity');
main::check((value_eq(main::state($restored)->{'room'}->{'host'}, main::state($watcher)->{'online'}->{'id'})), 'Spectator reconnect does not steal host after handoff');
main::dismissVictory($watcher);
$watcher->locator('#roomBtn')->click();
$watcher->locator('#onlineLeaveBtn')->click();
$watcher->close();
main::dismissVictory($restored);
$restored->locator('#roomBtn')->click();
$restored->locator('#onlineLeaveBtn')->click();
$restored->close();
$empty = main::load('WATCH HOST', ('New watch ' . format_value(int(time() * 1e9))), undef, undef, JSON::PP::true, undef);
main::watchJoin($empty, 'WATCH HOST');
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($empty)->{'room'}->{'players'}}), 0)); truth_value($boolean_value) ? (value_eq(main::state($empty)->{'room'}->{'host'}, main::state($empty)->{'online'}->{'id'})) : $boolean_value }), 'Missing watch room creates watching host, no hidden player');
$empty->locator('#addBotBtn')->click();
wait_js($empty, 'leqra.getState().room.players.length===1');
$empty->locator('#addBotBtn')->click();
wait_js($empty, 'leqra.getState().room.players.length===2');
$a = main::state($empty)->{'room'}->{'players'}->[0];
$empty->locator((('#roomRoster [data-team="' . format_value($a->{'id'})) . '"]'))->selectOption('1');
wait_js($empty, 'leqra.getState().room.canStart');
main::start($empty);
main::check((do { my $boolean_value = main::state($empty)->{'online'}->{'spectating'}; truth_value($boolean_value) ? !scalar(grep { my $p = $_; !((!truth_value((value_eq($p->{'kind'}, 'human'))))) } @{main::state($empty)->{'room'}->{'players'}}) : $boolean_value }), 'Spectating host can watch server bots play opposing teams');
main::dismissVictory($empty);
$empty->locator('#roomBtn')->click();
$empty->locator('#onlineLeaveBtn')->click();
$empty->close();
for $size (@{[[320, 568], [390, 844], [844, 390], [1365, 950]]}) {
    $h = main::load('SCREEN HOST', undef, $size, undef, undef, undef);
    $h->locator('#addLocalBtn')->click();
    $code = ('Screen ' . format_value(int(time() * 1e9)));
    $h->locator('#localRoomName')->fill($code);
    $h->locator('#copyInviteBtn')->click();
    main::conn($h);
    $p = main::load('VIEW', $code, $size, undef, JSON::PP::true, undef);
    main::screenshot($p, ('watch-prompt-' . $size->[0] . 'x' . $size->[1]));
    main::watchJoin($p, 'SCREEN VIEWER');
    main::membercount($h, 1);
    for $control (@{['toggleSpectateBtn', 'copySpectateBtn', 'startRoomBtn']}) {
        $h->locator(('#' . $control))->scrollIntoViewIfNeeded();
        $hit = evaluate_js($h->locator(('#' . $control)), '(e)=>{const r=e.getBoundingClientRect(),t=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return e===t||e.contains(t)}');
        main::check($hit, ($size . ': ' . $control . ' remains reachable'));
    }
    evaluate_js($h->locator('#roomScreen'), '(e)=>e.scrollTop=0');
    main::screenshot($h, ('room-' . $size->[0] . 'x' . $size->[1]));
    main::openGallery($h);
    main::screenshot($h, ('gallery-' . $size->[0] . 'x' . $size->[1]));
    $v = main::spectator($h, 'SCREEN VIEWER');
    $h->locator((('#spectatorList [data-swap-viewer="' . format_value($v->{'id'})) . '"]'))->click();
    $h->locator('#confirmSwapBtn')->scrollIntoViewIfNeeded();
    main::check($h->locator('#confirmSwapBtn')->isVisible(), ($size . ': host swap confirmation is reachable'));
    main::screenshot($h, ('swap-' . $size->[0] . 'x' . $size->[1]));
    $h->locator('#cancelSwapBtn')->click();
    main::closeGallery($h);
    main::start($h);
    wait_js($p, 'leqra.getState().phase==="playing"');
    main::screenshot($p, ('watching-' . $size->[0] . 'x' . $size->[1]));
    main::check((do { my $boolean_value = $p->locator('#spectatorBanner')->isVisible(); truth_value($boolean_value) ? $p->locator('#touchControls')->isHidden() : $boolean_value }), ($size . ': spectator sees watch banner without inactive touch controls'));
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), ($size . ': spectator UI has no horizontal overflow'));
    main::openGallery($p);
    main::check((contains_value($p->locator('#spectatorList')->innerText(), 'SCREEN VIEWER')), ($size . ': watcher can view spectator names during match'));
    main::closeGallery($p);
    $p->close();
    $h->close();
}
main::check((!truth_value($errors)), 'No JavaScript page errors across spectator scenarios');
$browser->close();
$report = {'version' => '3.3.0', 'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'page_errors' => $errors, 'limits' => 'Chromium emulation; exact assets, synthetic Location/History/storage, real loopback Go fixture. No physical devices/public internet/actual navigation.'};
$out->child('report.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text({'passed' => scalar(@{$checks}), 'errors' => $errors})), "\n");
