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

my ($unused, $a, $after, $assets, $bar, $before, $box, $browser, $buff, $cdp, $checks, $code, $contexts, $errors, $fb, $gen, $hc, $host, $id, $item, $offline, $oldcount, $opts, $out, $p, $pages, $parser, $pc, $phone, $points, $pw, $report, $result, $root, $size, $st, $stats, $t, $tc, $tiny, $wc, $wide);
# v2.5 actual-client power-up checks against the opt-in, loopback-only fixture.
# LEQRA_BROWSER_FIXTURE=1 go test -run '^TestBrowserFixture$' -timeout 30m
# perl tests/powerups_browser.pl http://127.0.0.1:8790 --isolated
# The production app has no power-grant or test-map HTTP endpoints.
$parser = {};
$a = do { my %args = ('url' => 'http://127.0.0.1:8790', 'isolated' => undef, 'browser' => undef, 'output' => 'test-output/powerups'); my $help; GetOptions('isolated!' => \$args{'isolated'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl powerups_browser.pl url --isolated --browser --output
'; if ($help) { print 'Usage: perl powerups_browser.pl url --isolated --browser --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2)->child('web');
$assets = asset_directory($root);
$out = path($a->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub state {
    my ($p) = @_;
    return evaluate_js($p, 'leqra.getState()');
}
sub call {
    my ($code, $power, $player, $speed, $shield, $cover) = @_;
    my ($req, $res);
    $power //= '';
    $player //= 0;
    $speed //= JSON::PP::false;
    $shield //= JSON::PP::false;
    $cover //= JSON::PP::false;
    $req = HTTP::Request->new('POST', ($a->{'url'} . '/_fixture/powerups'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'power' => $power, 'player' => $player, 'speed' => $speed, 'shield' => $shield, 'cover' => $cover})));
    $res = request_ok($req);
    return decode_json($res->content);
}
$pw = start_playwright();
my $playwright = $pw;
$opts = {'headless' => JSON::PP::true};
if (truth_value($a->{'browser'})) {
    $opts->{'executablePath'} = $a->{'browser'};
}
$browser = $pw->launch(type => 'chrome', %{$opts});
$contexts = [];
sub load {
    my ($name, $code, $size) = @_;
    my ($context, $html, $js, $mobile, $p, $pos, $setup, $url);
    $name //= 'PILOT';
    $code //= '';
    $size //= [1365, 950];
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $context = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $context);
    $p = $context->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $url = (($a->{'url'} . '/?test=1') . (truth_value($code) ? ('&room=' . $code) : ''));
    $setup = 'window.__sockets=[];window.__messages=[];
const RealSocket=WebSocket;window.WebSocket=class extends RealSocket{constructor(...a){super(...a);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}};
';
    if (truth_value($a->{'isolated'})) {
        $setup .= replace_text('function store(data){return {getItem:k=>data[k]??null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':NAME,\'leqra.muted\':\'1\'})});Object.defineProperty(window,\'sessionStorage\',{value:store({})});', 'NAME', json_text($name));
        $html = replace_text(replace_text(replace_text(replace_re('<link[^>]*>', '', $root->child('index.html')->slurp_utf8), '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', ''), '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
        $p->setContent($html);
        evaluate_js($p, (('()=>{' . $setup) . '}'));
        $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
        $pos = rindex($js, '})()');
        $js = ((substr($js, 0, $pos - 0) . ('})(new URL(' . json_text($url) . '));')) . substr($js, ($pos + 4)));
        $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
        $p->addScriptTag({content => $js});
    } else {
        $p->addInitScript(($setup . ('localStorage.setItem("leqra.name",' . json_text($name) . ');localStorage.setItem("leqra.muted","1");')));
        $p->goto($url);
    }
    wait_js($p, 'window.leqra');
    return [$p, $context];
}
my $tuple_52_1 = main::load('OFFLINE');
$offline = $tuple_52_1->[0];
$unused = $tuple_52_1->[1];
$result = evaluate_js($offline, '()=>{
 const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
 const setup=()=>{T.setMode(\'solo\');T.resetPreview();T.setPhase(\'playing\');T.clearBullets();const w=leqra.getState().world;
  T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
  T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0}));return T.tanks;
 };
 let ts=setup();T.grantPower(ts[0],\'homing\');T.grantPower(ts[0],\'speed\');T.grantPower(ts[0],\'shield\');ok(ts[0].power===\'homing\'&&ts[0].charges===3&&ts[0].speedTime===10&&ts[0].shield===10,\'Offline independent weapon, speed and shield\');
 for(const kind of [\'homing\',\'grenade\']){ts=setup();T.grantPower(ts[0],kind);for(let i=0;i<3;i++){ts[0].cooldown=0;ok(T.fire(ts[0]),\'Offline \'+kind+\' charge \'+(i+1));}ok(!ts[0].power&&T.bullets.filter(b=>b.kind===kind).length===3,\'Offline \'+kind+\' depletes after three shots\');}
 ts=setup();ts[0].x=400;ts[0].y=280;ts[1].x=100;ts[1].y=210;ts[2].x=180;
 const missile={kind:\'homing\',owner:1,target:-1,x:135,y:210,vx:235,vy:0,r:5,age:.2,life:4.8};T.steerMissile(missile,1/60);ok(missile.target===0&&missile.vy>0,\'Bot missile locks only the human, never its closer ally\');
 ts=setup();ts[0].x=150;ts[1].x=170;ts[2].x=190;ts[1].shield=10;ts[2].shield=10;
 T.detonate({kind:\'grenade\',owner:1,x:170,y:210,color:ts[1].color,dead:false});ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[1].shield===10&&ts[2].shield===10,\'Bot grenade cannot kill bots or consume their shields\');
 ts=setup();ts[0].x=100;ts[1].x=150;T.detonate({kind:\'grenade\',owner:0,x:130,y:210,color:ts[0].color,dead:false});ok(!ts[0].alive&&!ts[1].alive,\'Player grenade hurts the owner and enemy together\');
 ts=setup();ts[0].x=120;ts[1].x=280;T.walls.push({x:248,y:0,w:8,h:500});T.detonate({kind:\'grenade\',owner:0,x:225,y:210,color:ts[0].color,dead:false});ok(!ts[0].alive&&ts[1].alive,\'Offline grenade damage blocked by solid wall\');
 ts=setup();ts[1].x=190;T.grantPower(ts[0],\'grenade\');T.fire(ts[0]);for(let i=0;i<48;i++)T.updateBullets(1/120);ok(ts[1].alive&&T.bullets.length===1,\'Offline grenade rolls past tanks without contact detonation\');
 const predicted=T.grenadeForecast(T.bullets[0]);ts[1].x=predicted.x;ts[1].y=predicted.y;for(let i=0;i<553;i++)T.updateBullets(1/120);ok(T.bullets.length===0&&!ts[1].alive,\'Offline grenade fuse detonates and eliminates nearby enemy\');
 ts=setup();T.grantPower(ts[0],\'speed\');const x=ts[0].x;window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:\'KeyW\'}));T.humanControl(ts[0],1/60);window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:\'KeyW\'}));ok(Math.abs(ts[0].x-x-128*1.65/60)<1e-6,\'Offline super speed uses boosted keyboard movement\');
 ts=setup();T.grantPower(ts[1],\'homing\');ts[0].x=400;ts[1].x=120;ts[1].angle=0;ok(!!T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0),\'Bot recognizes a homing firing opportunity\');ok(!T.evaluateBotShot(ts[1],0,ts[2],{lead:1},0),\'Bot refuses an allied firing target\');
 ts=setup();T.grantPower(ts[1],\'grenade\');ts[1].x=100;ts[0].x=380;ok(!!T.evaluateBotShot(ts[1],0,ts[0],{lead:1},0),\'Bot evaluates grenade landing point and blast\');
 T.setPhase(\'menu\');T.resetPreview();return passed;
 }');
for $item (@{$result}) {
    main::check(JSON::PP::true, $item);
}
$offline->close();
my $tuple_78_1 = main::load('HOST');
$host = $tuple_78_1->[0];
$hc = $tuple_78_1->[1];
$host->locator('[data-mode=online]')->click();
$host->locator('#createRoomBtn')->click();
wait_js($host, 'leqra.getState().online?.connected');
$code = main::state($host)->{'online'}->{'code'};
my $tuple_79_1 = main::load('PHONE', $code, [390, 844]);
$phone = $tuple_79_1->[0];
$pc = $tuple_79_1->[1];
my $tuple_79_39 = main::load('POCKET', $code, [320, 568]);
$tiny = $tuple_79_39->[0];
$tc = $tuple_79_39->[1];
my $tuple_79_77 = main::load('WIDE', $code, [844, 390]);
$wide = $tuple_79_77->[0];
$wc = $tuple_79_77->[1];
$pages = [$host, $phone, $tiny, $wide];
for $p (@{$pages}) {
    wait_js($p, 'leqra.getState().online?.players.length===4');
    $p->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $p (@{$pages}) {
    wait_js($p, 'leqra.getState().phase==="playing"');
}
sub scenario {
    my ($power, $player, $speed, $shield, $cover) = @_;
    my ($data, $p);
    $power //= '';
    $player //= 0;
    $speed //= JSON::PP::false;
    $shield //= JSON::PP::false;
    $cover //= JSON::PP::false;
    $data = main::call($code, $power, $player, $speed, $shield, $cover);
    for $p (@{$pages}) {
        wait_js($p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g)', $data->{'generation'}, {});
        $Leqra::Browser::HANDLE->await($p->waitForTimeout(100));
    }
    return $data->{'generation'};
}
$gen = main::scenario('homing', undef, JSON::PP::true, JSON::PP::true, undef);
for $p (@{$pages}) {
    wait_js($p, 'leqra.getState().tanks.find(t=>t.id===0)?.power==="homing"');
}
main::check(!scalar(grep { my $p = $_; !(((([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t) : () } @{main::state($p)->{'tanks'}}]->[0] // undef)->{'speedTime'} > 0))) } @{$pages}), 'All four clients receive concurrent missile and speed state');
main::check((do { my $boolean_value = (contains_value($host->locator('#weaponLabel')->innerText(), 'HOMING')); truth_value($boolean_value) ? (contains_value($host->locator('#weaponLabel')->innerText(), '×3')) : $boolean_value }), 'HUD displays equipped missiles and remaining charges');
main::check((do { my $boolean_value = (contains_value($host->locator('#buffLabel')->innerText(), 'SPEED')); truth_value($boolean_value) ? (contains_value($host->locator('#buffLabel')->innerText(), 'SHIELD')) : $boolean_value }), 'HUD shows independent speed and shield timers');
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
$host->keyboard()->up('Space');
for $p (@{$pages}) {
    wait_js($p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"))', $gen, {});
}
main::check(JSON::PP::true, 'Homing missile is server-created and broadcast to all four clients');
wait_js($host, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.target===1&&b.vy>1))', $gen, {});
main::check(JSON::PP::true, 'Live missile changes direction and locks an opponent on the server');
$host->screenshot({path => format_value($out->child('homing-desktop.png'))});
wait_js($host, 'leqra.getState().tanks.find(t=>t.id===1)?.alive===false', undef, {timeout => 6000});
main::check(JSON::PP::true, 'Live homing hit is confirmed by server damage');
$gen = main::scenario('grenade');
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
$host->keyboard()->up('Space');
wait_js($host, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="grenade"&&b.life<4.7))', $gen, {});
main::check(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 1))) ? ($t) : () } @{main::state($host)->{'tanks'}}]->[0] // undef)->{'alive'}, 'Live grenade does not cause immediate contact damage');
$host->screenshot({path => format_value($out->child('grenade-fuse-desktop.png'))});
$Leqra::Browser::HANDLE->await($host->waitForTimeout(1350));
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(60));
$host->keyboard()->up('Space');
for $p (@{$pages}) {
    wait_js($p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.radius===110))', $gen, {});
}
main::check(JSON::PP::true, 'All clients receive authoritative owner-triggered blast event');
wait_js($host, 'leqra.getState().tanks.find(t=>t.id===1)?.alive===false');
main::check(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t) : () } @{main::state($host)->{'tanks'}}]->[0] // undef)->{'alive'}, 'Thrower outside blast survives while nearby enemy is eliminated');
$gen = main::scenario('homing', 1, JSON::PP::true, JSON::PP::true, undef);
wait_js($phone, 'leqra.getState().tanks.find(t=>t.id===1)?.speedTime>0');
$before = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, 1))) ? ($t) : () } @{main::state($phone)->{'tanks'}}]->[0] // undef);
$cdp = $pc->newCDPSession($phone);
$st = $phone->locator('#stickBase')->boundingBox();
$fb = $phone->locator('#fireBtn')->boundingBox();
$points = [{'x' => (($st->{'x'} + ($st->{'width'} / 2)) + 35), 'y' => ($st->{'y'} + ($st->{'height'} / 2)), 'id' => 11}, {'x' => ($fb->{'x'} + ($fb->{'width'} / 2)), 'y' => ($fb->{'y'} + ($fb->{'height'} / 2)), 'id' => 12}];
$cdp->send('Input.dispatchTouchEvent', {'type' => 'touchStart', 'touchPoints' => $points});
$Leqra::Browser::HANDLE->await($phone->waitForTimeout(360));
$after = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, 1))) ? ($t) : () } @{main::state($phone)->{'tanks'}}]->[0] // undef);
main::check(((($after->{'x'} - $before->{'x'}) > 45)), 'Boosted mobile tank moves while firing missiles');
main::check(evaluate_js($phone->locator('#fireBtn'), 'e=>e.classList.contains("held")'), 'Mobile fire remains held with active joystick');
main::check(evaluate_js($phone, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.owner===1))', $gen), 'Touch Fire creates a server-owned missile');
$phone->screenshot({path => format_value($out->child('mobile-speed-missile.png'))});
$cdp->send('Input.dispatchTouchEvent', {'type' => 'touchEnd', 'touchPoints' => []});
$Leqra::Browser::HANDLE->await($phone->waitForTimeout(70));
main::check((!truth_value(evaluate_js($phone->locator('#fireBtn'), 'e=>e.classList.contains("held")'))), 'Touch release stops held fire');
for my $item (@{[[$tiny, 2, '320x568'], [$wide, 3, '844x390']]}) {
    my $tuple_126_5 = $item;
    my $p = $tuple_126_5->[0];
    my $id = $tuple_126_5->[1];
    my $size = $tuple_126_5->[2];
    main::scenario('grenade', $id, JSON::PP::true, JSON::PP::true, undef);
    $Leqra::Browser::HANDLE->await($p->waitForTimeout(200));
    main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow with full loadout: ' . $size));
    my $box = $p->locator('#weaponLabel')->boundingBox();
    my $buff = $p->locator('#buffLabel')->boundingBox();
    my $bar = $p->locator('.underbar')->boundingBox();
    my $stats = $p->locator('#bestInline')->boundingBox();
    main::check((do { my $boolean_value = ((($box->{'x'} + $box->{'width'}) <= $stats->{'x'})); truth_value($boolean_value) ? do { my $boolean_value = ((($buff->{'x'} + $buff->{'width'}) <= $stats->{'x'})); truth_value($boolean_value) ? ((($buff->{'y'} + $buff->{'height'}) <= ($bar->{'y'} + $bar->{'height'}))) : $boolean_value } : $boolean_value }), ('Weapon, buffs and latency fit without overlap: ' . $size));
    $p->screenshot({path => format_value($out->child((('full-loadout-' . $size) . '.png')))});
}
main::scenario('grenade', 0, JSON::PP::true, undef, undef);
$oldcount = evaluate_js($host, '__sockets.length');
evaluate_js($host, '__sockets.at(-1).close(4000,"Power reconnect test")');
wait_js($host, 'n=>__sockets.length>n&&leqra.getState().online?.connected', $oldcount, {timeout => 9000});
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'online'}->{'id'}, 0)); truth_value($boolean_value) ? (value_eq(([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t) : () } @{main::state($host)->{'tanks'}}]->[0] // undef)->{'power'}, 'grenade')) : $boolean_value }), 'Reconnection preserves authoritative power-up and identity');
wait_js($host, 'leqra.getState().tanks.find(t=>t.id===0)?.speedTime===0', undef, {timeout => 9000});
main::check(JSON::PP::true, 'Super speed expires in the browser after the server timer');
main::check((!truth_value($errors)), 'No JavaScript runtime errors in offline/new online power-ups');
$report = {'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'javascript_errors' => $errors, 'isolated_assets' => $a->{'isolated'}, 'test_only_power_fixture' => JSON::PP::true, 'browser_version' => $browser->version(), 'layouts' => [[1365, 950], [390, 844], [320, 568], [844, 390]]};
$out->child('powerups-results.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text($report, 1)), "\n");
$browser->close();
