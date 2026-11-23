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

my ($ap, $args, $assets, $beams, $browser, $cdp, $checks, $code, $contexts, $e, $errors, $gen, $history, $host, $i, $invite, $label, $name, $offline, $old, $out, $p, $pages, $phone, $pts, $pw, $random, $rect, $restricted, $result, $resumed, $root, $session, $size, $stickRect, $t, $tiny, $wide);
# v2.6 shipped-client checks. Run TestBrowserFixture, then this script.
# The restricted browser cannot navigate to local pages. Assets, storage, location
# and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
# History calls and encoded invite contents are checked, not real browser navigation.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:8790', 'browser' => '/usr/bin/chromium', 'output' => 'test-output/expansion'); my $help; GetOptions('browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl expansion_browser.pl url --browser --output
'; if ($help) { print 'Usage: perl expansion_browser.pl url --browser --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2)->child('web');
$assets = asset_directory($root);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub check {
    my ($v, $label) = @_;
    assert_ok($v, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub state {
    my ($p) = @_;
    return evaluate_js($p, 'leqra.getState()');
}
sub fixture {
    my ($code, $power, $player, $speed, $shield, $cover) = @_;
    my ($req, $res);
    $power //= '';
    $player //= 0;
    $speed //= JSON::PP::false;
    $shield //= JSON::PP::false;
    $cover //= JSON::PP::false;
    $req = HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/powerups'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'power' => $power, 'player' => $player, 'speed' => $speed, 'shield' => $shield, 'cover' => $cover})));
    $res = request_ok($req);
    return decode_json($res->content);
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
$contexts = [];
sub load {
    my ($name, $code, $size, $session, $history_throws) = @_;
    my ($context, $html, $js, $mobile, $p, $pos, $url, $ws);
    $name //= 'PILOT';
    $code //= undef;
    $size //= [1365, 950];
    $session //= undef;
    $history_throws //= JSON::PP::false;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $context = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $context);
    $p = $context->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $url = ('http://game.test/tanks/?test=1' . (truth_value((defined($code))) ? ('&' . query_string({'room' => $code})) : ''));
    $ws = (replace_text(replace_text($args->{'url'}, 'http:', 'ws:'), 'https:', 'wss:') . '/ws');
    $html = replace_text(replace_text(replace_text(replace_re('<link[^>]*>', '', $root->child('index.html')->slurp_utf8), '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', ''), '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
    $p->setContent($html);
    evaluate_js($p, '([url,ws,name,session,historyThrows])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied=\'\';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;window.WebSocket=class extends RealSocket{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':name,\'leqra.muted\':\'1\'})});
   Object.defineProperty(window,\'sessionStorage\',{value:store(session?{\'leqra.session\':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{if(historyThrows)throw Error(\'Restricted History\');__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});
  }', [$url, $ws, $name, $session, $history_throws]);
    $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
    $pos = rindex($js, '})()');
    $js = ((substr($js, 0, $pos - 0) . '})(window.__location);') . substr($js, ($pos + 4)));
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    return $p;
}
sub connected {
    my ($p) = @_;
    wait_js($p, 'leqra.getState().online?.connected', undef, {timeout => 10000});
}
$offline = main::load('OFFLINE');
$result = evaluate_js($offline, '()=>{
  const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
  const setup=()=>{T.setMode(\'solo\');T.resetPreview();T.setPhase(\'playing\');T.clearBullets();const w=leqra.getState().world;
   T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
   T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0}));return T.tanks;
  };
  let ts=setup();T.grantPower(ts[0],\'laser\');T.grantPower(ts[0],\'shield\');T.grantPower(ts[0],\'speed\');
  ok(ts[0].power===\'laser\'&&ts[0].charges===3&&ts[0].shield===10&&ts[0].speedTime===6,\'Offline laser grants three shots alongside speed and shield\');
  ok(T.fire(ts[0])&&!ts[1].alive&&ts[2].alive&&ts[0].alive&&T.bullets.length===0,\'Offline laser instantly stops at first opponent, never hits owner\');
  ok(!T.fire(ts[0])&&ts[0].charges===2,\'Offline laser cooldown prevents double fire\');
  ok(T.traces.length>0&&T.traces.at(-1).endX>ts[0].x,\'Offline beam visual is generated\');
  ts=setup();ts[1].shield=10;T.grantPower(ts[0],\'laser\');T.fire(ts[0]);ok(ts[1].alive&&ts[1].shield===0&&ts[2].alive,\'Offline shield absorbs laser and protects tank behind it\');
  ts=setup();ts[0].x=129;T.walls.push({x:150,y:0,w:8,h:500});T.grantPower(ts[0],\'laser\');T.fire(ts[0]);ok(ts[1].alive&&T.traces.at(-1).points[1].x<=147,\'Offline barrel cannot shoot laser through nearby wall\');
  ts=setup();ts[1].x=100;ts[2].x=180;ts[2].shield=10;ts[0].x=400;T.grantPower(ts[1],\'laser\');
  ok(T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0)?.target===0,\'Laser bot finds player beyond its teammate\');
  T.fire(ts[1]);ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[2].shield===10,\'Bot laser passes through allies without damaging shields\');
  ts=setup();ts[0].angle=-Math.PI/2;T.grantPower(ts[0],\'laser\');for(let i=0;i<3;i++){ts[0].cooldown=0;T.fire(ts[0]);}
  ok(!ts[0].power&&ts[0].charges===0,\'Offline laser expires after three shots\');
  T.setMode(\'duel\');T.startRound();ok(T.pickups.length===2,\'Local duel starts with two power-ups\');
  T.setMode(\'solo\');T.startRound();ok(T.pickups.length===2,\'Solo starts with two power-ups\');
  for(let i=0;i<30;i++)T.spawnPower();ok(T.pickups.length===5,\'Offline arena keeps at most five power-ups\');
  const seen=new Set();for(let i=0;i<300;i++){T.pickups.splice(0);T.spawnPower();T.pickups.forEach(p=>seen.add(p.type))}ok(seen.size===7&&seen.has(\'laser\'),\'All seven pickup types spawn offline\');
  for(const name of [\'a\',\'café + & #/?=\',\'🎮 家族\',\'<img src=x onerror=alert(1)>\',\'💥\'.repeat(128)])ok(T.validRoomCode(T.cleanRoomCode(name)),\'Client accepts room text: \'+name.slice(0,20));
  for(const name of [\'\', \' \', \'x\\u0000y\',\'x\\ny\',\'a\'.repeat(129),\'💥\'.repeat(129),\'\\ud800\',\'\\u200b\'])ok(!T.validRoomCode(T.cleanRoomCode(name)),\'Client rejects blank/control/oversize: \'+JSON.stringify(name.slice(0,10)));
  ok(T.cleanRoomCode(\'abc234\')===\'ABC234\'&&T.cleanRoomCode(\'Room + 🛡️\')===\'Room + 🛡️\',\'Custom text preserved; old codes remain case-insensitive\');
  T.setPhase(\'menu\');T.resetPreview();return passed;
 }');
for $label (@{$result}) {
    main::check(JSON::PP::true, $label);
}
$offline->close();
$host = main::load('HOST');
$host->locator('[data-mode=online]')->click();
$code = ('Adam\'s tanks + café & 💥 #/? = ' . unpack("H*", random_bytes(2)));
$host->locator('#joinCode')->fill($code);
main::check((value_eq($host->locator('#joinCode')->inputValue(), $code)), 'Room field keeps arbitrary text while typing');
$host->locator('#createRoomBtn')->click();
main::connected($host);
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'online'}->{'code'}, $code)); truth_value($boolean_value) ? (value_eq(main::state($host)->{'online'}->{'id'}, 0)) : $boolean_value }), 'Create uses supplied arbitrary room name and assigns host');
$history = evaluate_js($host, '__historyCalls');
$invite = evaluate_js($host, '__location.href');
main::check((do { my $boolean_value = (value_eq(scalar(@{$history}), 1)); truth_value($boolean_value) ? (value_eq((query_values(URI->new($invite)->query)->{'room'} // undef), [$code])) : $boolean_value }), 'Welcome updates History exactly once with encoded room name');
main::check((do { my $boolean_value = (value_eq([keys %{query_values(URI->new($invite)->query)}], ['room'])); truth_value($boolean_value) ? (!truth_value(URI->new($invite)->fragment())) : $boolean_value }), 'Address is invite-only: no test flag, token or fragment');
$host->locator('#copyInviteBtn')->click();
wait_js($host, '__copied.length>0');
main::check((value_eq(evaluate_js($host, '__copied'), $invite)), 'Copy Invite and updated address use exactly the same URL');
main::check((value_eq(evaluate_js($host, '__sockets.length'), 1)), 'Address update never reloads or creates another socket');
$phone = main::load('PHONE', $code, [390, 844]);
$tiny = main::load('TINY', $code, [320, 568]);
$wide = main::load('WIDE', $code, [844, 390]);
$pages = [$host, $phone, $tiny, $wide];
for my $item (@{[map { [$_, $pages->[$_]] } 0 .. $#{$pages}]}) {
    my $tuple_94_5 = $item;
    my $i = $tuple_94_5->[0];
    my $p = $tuple_94_5->[1];
    main::connected($p);
    wait_js($p, 'leqra.getState().online.players.length===4');
    main::check((value_eq(main::state($p)->{'online'}->{'code'}, $code)), ('Encoded invite joins same custom-name room ' . format_value($i)));
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow in custom-name room ' . format_value($i)));
    main::check(evaluate_js($p->locator('#pauseBtn'), 'e=>e.getBoundingClientRect().right<=innerWidth'), ('Header controls stay on-screen ' . format_value($i)));
    $p->screenshot({path => format_value($out->child(('room-' . $i . '.png')))});
}
main::check(!scalar(grep { my $p = $_; !((value_eq(evaluate_js($p, '__sent.filter(m=>m.type==="join").length'), 1))) } @{array_slice($pages, 1, undef)}), 'Invites directly join once without extra click');
$phone->locator('#roomCallsign')->fill('NEW PHONE');
$phone->locator('#roomCallsignForm button')->click();
wait_js($host, 'leqra.getState().online.players.some(p=>p.name==="NEW PHONE")');
main::check(JSON::PP::true, 'In-room rename still broadcasts in custom-name room');
for $p (@{$pages}) {
    $p->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $p (@{$pages}) {
    wait_js($p, 'leqra.getState().phase==="playing"');
}
main::check(((main::state($host)->{'pickupCount'} >= 2)), 'Online match starts with two power-ups');
sub scenario {
    my ($power, $player, $speed, $shield, $cover) = @_;
    my ($data, $p);
    $power //= 'laser';
    $player //= 0;
    $speed //= JSON::PP::false;
    $shield //= JSON::PP::false;
    $cover //= JSON::PP::false;
    $data = main::fixture($code, $power, $player, $speed, $shield, $cover);
    for $p (@{$pages}) {
        wait_js($p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g)', $data->{'generation'}, {});
        $Leqra::Browser::HANDLE->await($p->waitForTimeout(70));
    }
    return $data->{'generation'};
}
$gen = main::scenario(undef, undef, JSON::PP::true, JSON::PP::true, undef);
wait_js($host, 'document.getElementById("weaponLabel").textContent.includes("LASER")');
main::check((contains_value($host->locator('#weaponLabel')->innerText(), '×3')), 'Online laser HUD shows three charges');
main::check((do { my $boolean_value = (contains_value($host->locator('#buffLabel')->innerText(), 'SPEED')); truth_value($boolean_value) ? (contains_value($host->locator('#buffLabel')->innerText(), 'SHIELD')) : $boolean_value }), 'Laser can coexist with speed and shields online');
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(65));
$host->keyboard()->up('Space');
for $p (@{$pages}) {
    wait_js($p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"))', $gen, {});
}
main::check(JSON::PP::true, 'All four clients receive server laser beam endpoints');
wait_js($host, '!leqra.getState().tanks.find(t=>t.id===1).alive');
main::check((value_eq(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t) : () } @{main::state($host)->{'tanks'}}]->[0] // undef)->{'charges'}, 2)), 'Server consumes one charge for one laser hit');
main::check((value_eq(main::state($host)->{'bulletCount'}, 0)), 'Online laser is instantaneous, not a delayed shell');
$gen = main::scenario(undef, undef, undef, undef, JSON::PP::true);
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(50));
$host->keyboard()->up('Space');
$host->screenshot({path => format_value($out->child('laser-beam.png'))});
$Leqra::Browser::HANDLE->await($host->waitForTimeout(120));
main::check(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 1))) ? ($t) : () } @{main::state($host)->{'tanks'}}]->[0] // undef)->{'alive'}, 'Live server laser cannot hit opponent behind wall');
$beams = evaluate_js($host, 'g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.events||[]).filter(e=>e.type==="laser"&&e.generation===g)', $gen);
main::check((do { my $boolean_value = $beams; truth_value($boolean_value) ? !scalar(grep { my $e = $_; !((do { my $boolean_value = ((scalar(@{$e->{'points'}}) > 2)); truth_value($boolean_value) ? (($e->{'points'}->[1]->{'x'} <= 327.0001)) : $boolean_value })) } @{$beams}) : $boolean_value }), 'Laser beam reflects at the wall face without tunneling');
$gen = main::scenario(undef, 2, undef, undef, JSON::PP::true);
$cdp = $tiny->context()->newCDPSession($tiny);
$rect = $tiny->locator('#fireBtn')->boundingBox();
$stickRect = $tiny->locator('#stickBase')->boundingBox();
$pts = [{'x' => ($rect->{'x'} + ($rect->{'width'} / 2)), 'y' => ($rect->{'y'} + ($rect->{'height'} / 2)), 'id' => 1}, {'x' => (($stickRect->{'x'} + ($stickRect->{'width'} / 2)) + 20), 'y' => ($stickRect->{'y'} + ($stickRect->{'height'} / 2)), 'id' => 2}];
$cdp->send('Input.dispatchTouchEvent', {'type' => 'touchStart', 'touchPoints' => $pts});
$Leqra::Browser::HANDLE->await($tiny->waitForTimeout(85));
$cdp->send('Input.dispatchTouchEvent', {'type' => 'touchEnd', 'touchPoints' => []});
wait_js($tiny, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.owner===2))', $gen, {});
main::check(JSON::PP::true, 'Compact-phone Fire button fires server-authoritative laser');
$tiny->screenshot({path => format_value($out->child('phone-laser.png'))});
$session = evaluate_js($wide, 'JSON.parse(sessionStorage.getItem("leqra.session"))');
$old = main::state($wide)->{'online'}->{'id'};
$wide->close();
wait_js($host, 'id=>leqra.getState().online.players.some(p=>p.id===id&&!p.connected)', $old, {});
$resumed = main::load('RESTORED', $code, [844, 390], $session);
main::connected($resumed);
$pages->[(-1)] = $resumed;
main::check((value_eq(main::state($resumed)->{'online'}->{'id'}, $old)), 'Reconnect preserves seat in punctuation/Unicode room');
for $p (@{$pages}) {
    $p->close();
}
$random = main::load('RANDOM');
$random->locator('[data-mode=online]')->click();
$random->locator('#createRoomBtn')->click();
main::connected($random);
main::check((do { my $boolean_value = (value_eq(scalar(@{main::state($random)->{'online'}->{'code'}}), 6)); truth_value($boolean_value) ? (value_eq(evaluate_js($random, 'new URL(__location).searchParams.get("room")'), main::state($random)->{'online'}->{'code'})) : $boolean_value }), 'Blank-name Create sets random-code invite in address');
$random->locator('#leaveRoomBtn')->click();
main::check(evaluate_js($random, '!new URL(__location).searchParams.has("room")'), 'Leave removes room from address');
$random->close();
$restricted = main::load('RESTRICTED', undef, undef, undef, JSON::PP::true);
$restricted->locator('[data-mode=online]')->click();
$restricted->locator('#createRoomBtn')->click();
main::connected($restricted);
main::check(JSON::PP::true, 'History restrictions do not break room creation');
$restricted->close();
for my $item (@{[['<img src=x onerror=alert(1)> & <script>bad()</script>', [320, 568]], [('💥' x 128), [844, 390]]]}) {
    my $tuple_151_5 = $item;
    my $name = $tuple_151_5->[0];
    my $size = $tuple_151_5->[1];
    my $p = main::load('TEXT ONLY', $name, $size);
    main::connected($p);
    main::check((do { my $boolean_value = (value_eq($p->locator('#roomCodeDisplay')->innerText(), $name)); truth_value($boolean_value) ? (value_eq($p->locator('#roomCodeDisplay img,#roomCodeDisplay script')->count(), 0)) : $boolean_value }), 'Room name rendered as text, not HTML');
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), 'Long/special room name does not stretch viewport');
    main::check((do { my $boolean_value = $p->locator('#leaveRoomBtn')->isVisible(); truth_value($boolean_value) ? $p->locator('#copyInviteBtn')->isVisible() : $boolean_value }), 'Room actions remain available with a long name');
    $p->screenshot({path => format_value($out->child(('long-name-' . $size->[0] . '.png')))});
    $p->close();
}
main::check((!truth_value($errors)), 'No browser JavaScript errors');
$browser->close();
$out->child('results.json')->spew_utf8(json_text({'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limitations' => 'Chromium emulation. Exact shipped assets, synthetic URL/History/storage, real local Go WebSockets. No real navigation or physical-phone testing.'}, 1));
print(join(" ", 'PASSED', scalar(@{$checks})), "\n");
