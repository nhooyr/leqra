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

my ($after, $ap, $args, $assets, $b, $before, $box, $browser, $case, $checks, $client, $code, $code4, $conflict, $contexts, $dx0, $dx2, $errors, $fb, $field, $four, $fourhost, $fx, $fy, $gid, $got, $guest, $host, $i, $icons, $id, $inherited, $kind, $lid, $out, $ownerid, $p, $pw, $report, $root, $rows, $sb, $size, $sparse, $sx, $sy, $t, $ts, $web, $x, $x0, $x2);
# v3.1 regression of the unified-room exact-asset Chromium integration against opt-in loopback Go fixture.
# No production test endpoints. Navigation/History are adapters in this environment.
# Run LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 go test -run '^TestBrowserFixture$' -timeout 30m
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:18790', 'browser' => '/usr/bin/chromium', 'output' => 'test-output/unified-room'); my $help; GetOptions('url=s' => \$args{'url'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl unified_room_browser.pl --url --browser --output
'; if ($help) { print 'Usage: perl unified_room_browser.pl --url --browser --output
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
    my ($code, $path, $extra) = @_;
    my ($r);
    $path //= 'lane';
    $extra //= {};
    $r = request_ok(HTTP::Request->new('POST', (($args->{'url'} . '/_fixture/') . $path), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code}))));
    return decode_json($r->content);
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
$contexts = [];
sub load {
    my ($name, $code, $size, $session, $delay) = @_;
    my ($ctx, $html, $i, $js, $mobile, $p, $url);
    $name //= 'PILOT';
    $code //= undef;
    $size //= [1365, 950];
    $session //= undef;
    $delay //= 0;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $ctx = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $ctx);
    $p = $ctx->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->on('dialog', 'arguments[0].accept();');
    $html = replace_text(replace_text(replace_text(replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8), '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', ''), '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
    $p->setContent($html);
    $url = ('http://game.test/tanks/?test=1' . (truth_value((defined($code))) ? ('&' . query_string({'room' => $code})) : ''));
    evaluate_js($p, '([url,ws,name,session,delay])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied=\'\';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;
   window.WebSocket=class extends RealSocket{
    constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)));}
    send(v){__sent.push(JSON.parse(v));return super.send(v)}
   };
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':name,\'leqra.muted\':\'1\'})});
   Object.defineProperty(window,\'sessionStorage\',{value:store(session?{\'leqra.session\':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});
  }', [$url, (replace_text($args->{'url'}, 'http:', 'ws:') . '/ws'), $name, $session, $delay]);
    $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
    $i = rindex($js, '})()');
    $js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    return $p;
}
sub remove {
    my ($p, $id) = @_;
    $p->locator(('#roomRoster [data-kick-target="' . $id . '"]'))->click();
    $p->locator('#confirmKickBtn')->click();
    wait_js($p, 'id=>!leqra.getState().room.players.some(p=>p.id===id)', $id, {});
}
sub waitplayers {
    my ($p, $n) = @_;
    wait_js($p, 'n=>leqra.getState().room.players.length===n', $n, {});
}
sub press {
    my ($p, $key, $ms) = @_;
    $ms //= 80;
    $p->keyboard()->down($key);
    $Leqra::Browser::HANDLE->await($p->waitForTimeout($ms));
    $p->keyboard()->up($key);
}
sub connected {
    my ($p) = @_;
    wait_js($p, 'leqra.getState().online?.connected', undef, {timeout => 12000});
}
sub latest {
    my ($p) = @_;
    return evaluate_js($p, '__messages.filter(m=>m.type==="state").at(-1)');
}
sub menu {
    my ($p) = @_;
    main::dismissVictory($p);
    $p->locator('#roomBtn')->click();
}
sub ready {
    my ($p) = @_;
    main::dismissVictory($p);
    $p->locator('#readyBtn')->click();
}
sub room {
    my ($p) = @_;
    main::menu($p);
    $p->locator('#returnRoomBtn')->click();
    wait_js($p, '["menu","onlineLobby"].includes(leqra.getState().phase)');
}
sub team {
    my ($p, $id, $n) = @_;
    $p->locator(('#roomRoster [data-team="' . $id . '"]'))->selectOption(format_value($n));
    wait_js($p, '([id,n])=>leqra.getState().room.players.find(p=>p.id===id)?.team===n', [$id, $n], {});
    $Leqra::Browser::HANDLE->await($p->waitForTimeout(160));
}
sub start {
    my ($p) = @_;
    main::dismissVictory($p);
    $p->locator('#startRoomBtn')->click();
    wait_js($p, 'leqra.getState().phase==="playing"', undef, {timeout => 8000});
}
$host = main::load('ADAM');
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'mode'}, 'room')); truth_value($boolean_value) ? $host->locator('#roomScreen')->isVisible() : $boolean_value }), 'Startup is a local game room, not a mode chooser');
main::check((value_eq(evaluate_js($host, '__sockets.length'), 0)), 'Local room and solo play need no WebSocket');
main::check((value_eq([map { my $p = $_; $p->{'kind'} } @{main::state($host)->{'room'}->{'players'}}], ['human', 'bot', 'bot'])), 'Default roster is host plus two bots');
$host->locator('#roomCallsignForm input')->fill('CAPTAIN');
$host->locator('#roomCallsignForm button')->click();
main::check((value_eq(main::state($host)->{'room'}->{'players'}->[0]->{'name'}, 'CAPTAIN')), 'Callsign editable in local room');
$host->locator('[data-bot-difficulty="1"]')->selectOption('easy');
$host->locator('[data-bot-difficulty="2"]')->selectOption('hard');
main::check((value_eq([map { my $p = $_; ($p->{'difficulty'} // undef) } @{array_slice(main::state($host)->{'room'}->{'players'}, 1, undef)}], ['easy', 'hard'])), 'Individual Chill and Fierce bot settings');
$host->locator('#addLocalBtn')->click();
main::waitplayers($host, 4);
main::check((value_eq(main::state($host)->{'room'}->{'players'}->[3]->{'kind'}, 'local')), 'Second local player can use a nonadjacent roster slot');
main::check((do { my $boolean_value = $host->locator('#addBotBtn')->isDisabled(); truth_value($boolean_value) ? $host->locator('#addLocalBtn')->isDisabled() : $boolean_value }), 'Four-seat cap enforced in local room');
for $id (@{[1, 2]}) {
    main::team($host, $id, 1);
}
main::check($host->locator('#startRoomBtn')->isDisabled(), 'One-team local match cannot start');
for $id (@{[1, 2]}) {
    main::team($host, $id, 2);
}
main::start($host);
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($host)->{'tanks'}}), 4)); truth_value($boolean_value) ? (value_eq(evaluate_js($host, '__sockets.length'), 0)) : $boolean_value }), 'Four local participants play without server');
evaluate_js($host, '()=>{const T=__test,w=leqra.getState().world;T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{x:100,y:90+i*130,angle:0,invulnerable:100,cooldown:99}));}');
$host->keyboard()->down('KeyW');
$host->keyboard()->down('ArrowUp');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(550));
$host->keyboard()->up('KeyW');
$host->keyboard()->up('ArrowUp');
$ts = main::state($host)->{'tanks'};
main::check((do { my $boolean_value = (($ts->[0]->{'x'} > 140)); truth_value($boolean_value) ? (($ts->[3]->{'x'} > 140)) : $boolean_value }), 'Both local keyboard movement paths work simultaneously');
main::check(((abs(($ts->[0]->{'x'} - $ts->[3]->{'x'})) < 6)), 'Both local human tanks use the same movement speed');
evaluate_js($host, '()=>{__test.clearInput();__test.clearBullets();let t=__test.tanks.find(t=>t.id===3);t.cooldown=0;__test.grantPower(t,\'grenade\');t.charges=1;}');
main::press($host, 'Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(100));
main::check(evaluate_js($host, '__test.bullets.some(b=>b.owner===3&&b.kind==="grenade")'), 'Second local player Space throws grenade');
main::press($host, 'Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
main::check(evaluate_js($host, '!__test.bullets.some(b=>b.owner===3&&b.kind==="grenade")'), 'Second local player Space detonates final-charge grenade');
main::room($host);
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'mode'}, 'room')); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($host)->{'room'}->{'players'}}), 4)) : $boolean_value }), 'Return to local room retains roster');
main::remove($host, 2);
$inherited = ([map { my $x = $_; truth_value((value_eq($x->{'kind'}, 'bot'))) ? ($x->{'difficulty'}) : () } @{[reverse @{main::state($host)->{'room'}->{'players'}}]}]->[0] // 'normal');
$host->locator('#addBotBtn')->click();
main::waitplayers($host, 4);
main::check((value_eq(main::state($host)->{'room'}->{'players'}->[2]->{'difficulty'}, $inherited)), 'Add Bot uses the last roster bot difficulty');
main::remove($host, 2);
$code = (('Team room ' . format_value(int(time()))) . ' 💥 & +/#');
$host->locator('#localRoomName')->fill($code);
$host->locator('#copyInviteBtn')->click();
main::connected($host);
main::waitplayers($host, 3);
main::check((value_eq([map { my $p = $_; $p->{'kind'} } @{main::state($host)->{'room'}->{'players'}}], ['human', 'bot', 'local'])), 'Sharing imports the configured room rather than a replacement empty lobby');
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'room'}->{'players'}->[1]->{'difficulty'}, 'easy')); truth_value($boolean_value) ? (value_eq(main::state($host)->{'room'}->{'players'}->[2]->{'team'}, 1)) : $boolean_value }), 'Sharing preserves bot difficulty and local teammate');
main::check((value_eq(evaluate_js($host, 'new URL(__historyCalls.at(-1)).searchParams.get("room")'), $code)), 'Shared room URL uses accepted arbitrary Unicode name');
$host->locator('#copyInviteBtn')->click();
main::check((value_eq(evaluate_js($host, 'new URL(__copied).searchParams.get("room")'), $code)), 'Copy Invite matches room URL');
$conflict = main::load('CONFLICT');
$conflict->locator('#localRoomName')->fill($code);
$conflict->locator('#copyInviteBtn')->click();
wait_js($conflict, 'leqra.getState().mode==="room"&&document.querySelector("#roomStatus").textContent.includes("already in use")');
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($conflict)->{'room'}->{'players'}}), 3)); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($host)->{'room'}->{'players'}}), 3)) : $boolean_value }), 'Failed Share retains local roster and leaves existing online room untouched');
$conflict->close();
$guest = main::load('GUEST', $code, [390, 844]);
main::connected($guest);
main::waitplayers($host, 4);
main::check((do { my $boolean_value = $guest->locator('#roomScreen')->isVisible(); truth_value($boolean_value) ? (!truth_value($guest->locator('#joinDialog')->isVisible())) : $boolean_value }), 'Invite joins directly into same unified room');
$gid = main::state($guest)->{'online'}->{'id'};
$lid = ([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p->{'id'}) : () } @{main::state($host)->{'room'}->{'players'}}]->[0] // undef);
main::check((do { my $boolean_value = $guest->locator('#rosterTools')->isHidden(); truth_value($boolean_value) ? do { my $boolean_value = $guest->locator('#startRoomBtn')->isHidden(); truth_value($boolean_value) ? (value_eq($guest->locator('#roomRoster select')->count(), 0)) : $boolean_value } : $boolean_value }), 'Guest sees roster but cannot configure or start it');
main::team($host, $gid, 2);
main::ready($guest);
wait_js($host, '!document.querySelector("#startRoomBtn").disabled');
evaluate_js($guest, '()=>{const p=leqra.getState().room.players[0];__sockets.at(-1).send(JSON.stringify({type:\'configure\',target:p.id,member:p.member,team:4}));}');
wait_js($guest, '__messages.some(m=>m.type==="error"&&m.code==="not_host")');
main::check((value_eq(main::state($host)->{'room'}->{'players'}->[0]->{'team'}, 1)), 'Server rejects guest-forged team change');
main::start($host);
wait_js($guest, 'leqra.getState().phase==="playing"');
main::check((do { my $boolean_value = main::latest($host)->{'tanks'}->[1]->{'bot'}; truth_value($boolean_value) ? (value_eq(main::latest($host)->{'tanks'}->[1]->{'difficulty'}, 'easy')) : $boolean_value }), 'Online bots are server-simulated participants with selected difficulty');
main::fixture($code);
$Leqra::Browser::HANDLE->await($host->waitForTimeout(200));
$before = main::latest($host);
$x0 = $before->{'tanks'}->[0]->{'x'};
$x2 = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{$before->{'tanks'}}]->[0] // undef)->{'x'};
$host->keyboard()->down('KeyW');
$host->keyboard()->down('ArrowUp');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(650));
$host->keyboard()->up('KeyW');
$host->keyboard()->up('ArrowUp');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
$after = main::latest($host);
$dx0 = ($after->{'tanks'}->[0]->{'x'} - $x0);
$dx2 = (([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{$after->{'tanks'}}]->[0] // undef)->{'x'} - $x2);
main::check((do { my $boolean_value = (($dx0 > 60)); truth_value($boolean_value) ? (($dx2 > 60)) : $boolean_value }), 'Go server simulates both host keyboard pilots concurrently');
main::check(((abs(($dx0 - $dx2)) < 9)), 'Online secondary input uses independent prediction and acknowledgement');
main::check(evaluate_js($host, 'id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.forward)', $lid), 'Secondary input names owned seat explicitly');
$x0 = $after->{'tanks'}->[0]->{'x'};
$x2 = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{$after->{'tanks'}}]->[0] // undef)->{'x'};
$host->keyboard()->down('ArrowUp');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(380));
$host->keyboard()->up('ArrowUp');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(70));
$after = main::latest($host);
main::check((do { my $boolean_value = ((abs(($after->{'tanks'}->[0]->{'x'} - $x0)) < 9)); truth_value($boolean_value) ? (((([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{$after->{'tanks'}}]->[0] // undef)->{'x'} - $x2) > 35)) : $boolean_value }), 'Secondary movement does not steer or move primary');
main::fixture($code, 'powerups', {'player' => $lid, 'power' => 'grenade', 'missileScene' => 'range'});
$Leqra::Browser::HANDLE->await($host->waitForTimeout(250));
main::press($host, 'Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(160));
if (truth_value((!truth_value(scalar(grep { my $b = $_; (do { my $boolean_value = (value_eq($b->{'owner'}, $lid)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($b->{'kind'}, 'grenade')); truth_value($boolean_value) ? (($b->{'life'} > 4.5)) : $boolean_value } : $boolean_value }) } @{main::latest($host)->{'bullets'}}))))) {
    print(join(" ", 'DEBUG_SECONDARY', $lid, json_text(main::latest($host)), evaluate_js($host, '__sent.slice(-24)'), main::state($host)), "\n");
}
main::check(scalar(grep { my $b = $_; (do { my $boolean_value = (value_eq($b->{'owner'}, $lid)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($b->{'kind'}, 'grenade')); truth_value($boolean_value) ? (($b->{'life'} > 4.5)) : $boolean_value } : $boolean_value }) } @{main::latest($host)->{'bullets'}}), 'Server gives secondary grenade a five-second fuse');
main::press($host, 'Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(140));
main::check((!truth_value(scalar(grep { my $b = $_; (do { my $boolean_value = (value_eq($b->{'owner'}, $lid)); truth_value($boolean_value) ? (value_eq($b->{'kind'}, 'grenade')) : $boolean_value }) } @{main::latest($host)->{'bullets'}}))), 'Owned secondary grenade remotely detonates online');
evaluate_js($guest, 'id=>__sockets.at(-1).send(JSON.stringify({type:"input",player:id,seq:999,fire:true}))', $lid);
wait_js($guest, '__messages.some(m=>m.type==="error"&&m.code==="not_owned")');
main::check(JSON::PP::true, 'Other browser cannot control host secondary pilot');
$ownerid = main::state($host)->{'online'}->{'id'};
evaluate_js($host, '__sockets.at(-1).close(4001,"test interruption")');
wait_js($guest, 'leqra.getState().room.host===leqra.getState().online.id');
wait_js($host, '__messages.filter(m=>m.type==="welcome").length>=2&&leqra.getState().online.connected', undef, {timeout => 12000});
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'online'}->{'id'}, $ownerid)); truth_value($boolean_value) ? (value_eq(([map { my $p = $_; truth_value((value_eq($p->{'kind'}, 'local'))) ? ($p) : () } @{main::state($host)->{'room'}->{'players'}}]->[0] // undef)->{'owner'}, $ownerid)) : $boolean_value }), 'Reconnect restores both controlled seats after host handoff');
main::check((do { my $boolean_value = (value_eq(main::state($guest)->{'room'}->{'host'}, $gid)); truth_value($boolean_value) ? $guest->locator('#roomBtn')->isVisible() : $boolean_value }), 'Host handoff chooses real online human, not bot or local P2');
main::fixture($code);
$Leqra::Browser::HANDLE->await($host->waitForTimeout(300));
$x2 = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{main::latest($host)->{'tanks'}}]->[0] // undef)->{'x'};
main::press($host, 'ArrowUp', 350);
$Leqra::Browser::HANDLE->await($host->waitForTimeout(100));
main::check(((([map { my $t = $_; truth_value((value_eq($t->{'id'}, $lid))) ? ($t) : () } @{main::latest($host)->{'tanks'}}]->[0] // undef)->{'x'} > ($x2 + 25))), 'Secondary movement resumes after reconnect and host handoff');
main::menu($guest);
$guest->locator('#returnRoomBtn')->click();
wait_js($guest, 'leqra.getState().phase==="onlineLobby"');
wait_js($host, 'leqra.getState().phase==="onlineLobby"');
main::check((value_eq(scalar(@{main::state($guest)->{'room'}->{'players'}}), 4)), 'New host returns everyone to room without losing roster');
$guest->locator(('#roomRoster [data-kick-target="' . $ownerid . '"]'))->click();
$guest->locator('#confirmKickBtn')->click();
main::waitplayers($guest, 2);
main::check((!truth_value(scalar(grep { my $p = $_; (value_eq($p->{'kind'}, 'local')) } @{main::state($guest)->{'room'}->{'players'}}))), 'Kick owner also removes dependent local seat');
wait_js($host, 'leqra.getState().mode==="room"');
main::check($host->locator('#joinDialog')->isVisible(), 'Kicked controller returns locally and sees removal notice');
$host->close();
$guest->close();
for $size (@{[[320, 568], [390, 844], [844, 390]]}) {
    $p = main::load('PHONE', undef, $size, undef, undef);
    $p->locator('#addLocalBtn')->click();
    main::waitplayers($p, 4);
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth+1'), ('No horizontal overflow ' . format_value($size)));
    $p->locator('#startRoomBtn')->scrollIntoViewIfNeeded();
    $box = $p->locator('#startRoomBtn')->boundingBox();
    main::check((do { my $boolean_value = (defined($box)); truth_value($boolean_value) ? do { my $boolean_value = (($box->{'y'} >= 0)); truth_value($boolean_value) ? ((($box->{'y'} + $box->{'height'}) <= ($size->[1] + 1))) : $boolean_value } : $boolean_value }), ('Start button reachable ' . format_value($size)));
    $p->screenshot({path => format_value($out->child(('room-' . $size->[0] . 'x' . $size->[1] . '.png')))});
    main::dismissVictory($p);
    $p->locator('#startRoomBtn')->click();
    wait_js($p, 'leqra.getState().phase==="playing"');
    main::check($p->locator('#touchControls')->isVisible(), ('Mobile touch controls restored during match ' . format_value($size)));
    evaluate_js($p, '()=>{__test.tanks.forEach(t=>t.invulnerable=100);__test.tanks[0].cooldown=0;}');
    $Leqra::Browser::HANDLE->await($p->waitForTimeout(150));
    $client = $p->context()->newCDPSession($p);
    $sb = $p->locator('#stickBase')->boundingBox();
    $fb = $p->locator('#fireBtn')->boundingBox();
    $sx = (($sb->{'x'} + ($sb->{'width'} / 2)) + 27);
    $sy = ($sb->{'y'} + ($sb->{'height'} / 2));
    $fx = ($fb->{'x'} + ($fb->{'width'} / 2));
    $fy = ($fb->{'y'} + ($fb->{'height'} / 2));
    $client->send('Input.dispatchTouchEvent', {'type' => 'touchStart', 'touchPoints' => [{'x' => $sx, 'y' => $sy, 'id' => 1}, {'x' => $fx, 'y' => $fy, 'id' => 2}]});
    wait_js($p, '__test.bullets.some(b=>b.owner===0)', undef, {timeout => 3000});
    main::check(evaluate_js($p, 'document.querySelector("#stickKnob").style.transform!=="translate(0,0)"'), ('Simultaneous mobile steering and Fire ' . format_value($size)));
    $client->send('Input.dispatchTouchEvent', {'type' => 'touchEnd', 'touchPoints' => []});
    $p->screenshot({path => format_value($out->child(('playing-' . $size->[0] . 'x' . $size->[1] . '.png')))});
    $p->close();
}
$fourhost = main::load('FOUR HOST');
$fourhost->locator('#joinOtherBtn')->click();
$fourhost->locator('#createRoomBtn')->click();
main::connected($fourhost);
$code4 = main::state($fourhost)->{'online'}->{'code'};
$four = [@{[$fourhost]}, @{[map { my $i = $_; main::load(('PILOT ' . format_value($i)), $code4, (truth_value((value_eq($i, 1))) ? [390, 844] : [1365, 950])) } @{[1 .. 4 - 1]}]}];
for $p (@{$four}) {
    main::connected($p);
    main::waitplayers($p, 4);
}
for $id (@{[0 .. 4 - 1]}) {
    main::team($fourhost, $id, (1 + ($id % 2)));
}
for $p (@{array_slice($four, 1, undef)}) {
    main::ready($p);
}
wait_js($fourhost, '!document.querySelector("#startRoomBtn").disabled');
main::start($fourhost);
for $p (@{$four}) {
    wait_js($p, 'leqra.getState().phase==="playing"');
}
for my $item (@{[map { [$_, $four->[$_]] } 0 .. $#{$four}]}) {
    my $tuple_168_5 = $item;
    my $i = $tuple_168_5->[0];
    my $p = $tuple_168_5->[1];
    main::check((do { my $boolean_value = (value_eq(main::state($p)->{'online'}->{'id'}, $i)); truth_value($boolean_value) ? (value_eq(scalar(@{main::state($p)->{'tanks'}}), 4)) : $boolean_value }), ('Four-browser team match: distinct controller ' . format_value($i)));
}
main::fixture($code4, 'powerups', {'power' => 'laser', 'player' => 0});
$Leqra::Browser::HANDLE->await($fourhost->waitForTimeout(180));
main::press($fourhost, 'Space', 50);
for my $item (@{[map { [$_, $four->[$_]] } 0 .. $#{$four}]}) {
    my $tuple_170_5 = $item;
    my $i = $tuple_170_5->[0];
    my $p = $tuple_170_5->[1];
    wait_js($p, '__messages.some(m=>m.type==="state"&&(m.events||[]).some(e=>e.type==="laser"))');
    main::check(JSON::PP::true, ('Laser beam event reaches online team client ' . format_value($i)));
}
for $p (@{$four}) {
    $p->close();
}
$sparse = main::load('SPARSE');
main::remove($sparse, 1);
main::start($sparse);
evaluate_js($sparse, '()=>{const t=__test.tanks.find(t=>t.id===0);t.invulnerable=0;__test.hurt(t,{owner:2,kind:\'normal\'});}');
main::check((!truth_value(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t) : () } @{main::state($sparse)->{'tanks'}}]->[0] // undef)->{'alive'})), 'Removed roster slot does not break elimination by higher-ID bot');
$sparse->close();
$icons = main::load('ICONS');
$rows = evaluate_js($icons, '()=>{const result=[];for(const icon of document.querySelectorAll(\'canvas[data-power-icon]\')){const copy=document.createElement(\'canvas\');copy.width=copy.height=icon.width;const c=copy.getContext(\'2d\');c.setTransform(copy.width/26,0,0,copy.width/26,copy.width/2,copy.height/2);__test.powerIcon(icon.dataset.powerIcon,c);const a=c.getImageData(0,0,copy.width,copy.height).data,b=icon.getContext(\'2d\').getImageData(0,0,icon.width,icon.height).data;if(!a.some(v=>v>0)||!a.every((v,i)=>v===b[i]))throw Error(\'icon mismatch \'+icon.dataset.powerIcon);result.push(icon.dataset.powerIcon)}return result}');
for $kind (@{$rows}) {
    main::check(JSON::PP::true, ('Exact legend/maze icon pixels: ' . $kind));
}
for $case (@{decode_json($root->child('tests/missile-fixtures.json')->slurp_utf8)}) {
    $got = evaluate_js($icons, 'c=>{const T=__test;T.setMode(\'duel\');T.resetPreview();T.setPhase(\'playing\');T.clearBullets();T.setWorld(c.world);T.tanks.forEach((t,i)=>Object.assign(t,c.tanks[i]));const b={...c.bullet,dead:false,trail:[]};T.addBullet(b);for(let i=0;i<c.steps;i++){if(c.moveY)T.moveTank(T.tanks[1],0,c.moveY/60);T.updateBullets(1/60)}T.setPhase(\'menu\');return{bullet:b,alive:T.tanks[1].alive}}', $case);
    for $field (@{['x', 'y', 'vx', 'vy', 'life', 'age', 'rangeLeft', 'seekDelay', 'bounces', 'target']}) {
        main::check(((abs((($got->{'bullet'}->{$field} // 0) - ($case->{'expected'}->{$field} // 0))) < 1e-06)), ((('Go/JS aggressive missile parity ' . $case->{'name'}) . ' ') . $field));
    }
    main::check((value_eq($got->{'alive'}, $case->{'alive'})), ('Go/JS missile hit parity ' . $case->{'name'}));
}
evaluate_js($icons, '__test.createLocalRoom()');
$icons->screenshot({path => format_value($out->child('desktop-room.png'))});
main::check((!truth_value($errors)), ('No browser runtime errors: ' . format_value($errors)));
$report = {'version' => '3.2.0', 'assertions' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Chromium exact asset injection; synthetic Location/History/storage; real loopback Go sockets; no physical devices or public internet.'};
$out->child('report.json')->spew_utf8(json_text($report, 1));
$browser->close();
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
