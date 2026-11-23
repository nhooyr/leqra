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

my ($ap, $args, $assets, $b, $before, $checks, $code, $ctx, $errors, $gid, $guest, $hid, $host, $html, $i, $js, $label, $out, $p, $phone, $pid, $pw, $r, $req, $root, $seen, $setup, $viewer, $web);
# Real Go-backed Cannon trial with two keyboard pilots, a remote pilot and viewer.
# Only the loopback _test.go fixture arranges the cover/target and equips weapons.
# Controls, firing, collision, damage, snapshots and drawing are production code.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:8851', 'output' => 'test-output/cannon39-online'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl cannon39_online_browser.pl url --output
'; if ($help) { print 'Usage: perl cannon39_online_browser.pl url --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub check {
    my ($ok, $s) = @_;
    assert_ok($ok, $s);
    push(@{$checks}, $s);
    print(join(" ", 'PASS', $s), "\n");
}
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script src="[^"]+" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . ('})(new URL(' . json_text(($args->{'url'} . '/?test=1')) . '));')) . substr($js, ($i + 4)));
sub load {
    my ($c, $name) = @_;
    my ($p);
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, '()=>{const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.muted\':\'1\'})});Object.defineProperty(window,\'sessionStorage\',{value:store({})});}');
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    $p->locator('#joinOtherBtn')->click();
    $p->locator('#pilotName')->fill($name);
    return $p;
}
sub track {
    my ($p) = @_;
    evaluate_js($p, '()=>{window.wire39=[];__test.online.socket.addEventListener(\'message\',e=>{const m=JSON.parse(e.data);if(m.type===\'state\')wire39.push(m);});}');
}
sub cannon_seen {
    my ($p, $owner) = @_;
    return evaluate_js($p, 'owner=>{const shots=wire39.flatMap(s=>s.bullets).filter(b=>b.owner===owner&&b.kind===\'cannon\');return{count:shots.length,correct:shots.every(b=>b.r===10.5&&Math.abs(Math.hypot(b.vx,b.vy)-846)<.0001&&b.bounces===0),crossed:shots.some(b=>b.x>705),max:Math.max(0,...shots.map(b=>b.x))};}', $owner);
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
eval {
    $ctx = $b->newContext({viewport => {'width' => 1365, 'height' => 950}});
    $phone = $b->newContext({viewport => {'width' => 390, 'height' => 844}, isMobile => JSON::PP::true, hasTouch => JSON::PP::true, deviceScaleFactor => 2});
    $host = main::load($ctx, 'CANNON HOST');
    $host->locator('#createRoomBtn')->click();
    wait_js($host, 'leqra.getState().online?.connected');
    $code = evaluate_js($host, 'leqra.getState().online.code');
    $hid = evaluate_js($host, 'leqra.getState().online.id');
    $host->locator('#addLocalBtn')->click();
    wait_js($host, 'leqra.getState().room.players.length===2');
    $pid = evaluate_js($host, 'leqra.getState().room.players.find(p=>p.kind===\'local\').id');
    $host->locator('[data-room-mode="koth"]')->click();
    wait_js($host, 'leqra.getState().rules.mode===\'koth\'');
    $host->locator('#roomRulesBtn')->click();
    $host->locator('#rule-timeLimit')->fill('600');
    $host->locator('#rule-scoreTarget')->fill('300');
    $host->locator('#rule-pickupRate')->selectOption('off');
    $host->locator('#applyRulesBtn')->click();
    $guest = main::load($ctx, 'REMOTE TARGET');
    $guest->locator('#joinCode')->fill($code);
    $guest->locator('#joinRoomBtn')->click();
    wait_js($guest, 'leqra.getState().online?.connected');
    $gid = evaluate_js($guest, 'leqra.getState().online.id');
    $guest->locator('#readyBtn')->click();
    $viewer = main::load($phone, 'VIEWER');
    $viewer->locator('#joinCode')->fill($code);
    $viewer->locator('#joinRoomBtn')->click();
    wait_js($viewer, 'leqra.getState().online?.connected');
    evaluate_js($viewer, '()=>{const s=leqra.getState();__test.setPlayerSpectating(s.room.players.find(p=>p.id===s.online.id),true);}');
    wait_js($viewer, 'leqra.getState().online.spectating');
    if (truth_value((!truth_value(evaluate_js($guest, 'leqra.getState().room.players.find(p=>p.id===leqra.getState().online.id).ready'))))) {
        $guest->locator('#readyBtn')->click();
    }
    wait_js($host, '!document.querySelector("#startRoomBtn").disabled');
    $host->locator('#startRoomBtn')->click();
    for $p (@{[$host, $guest, $viewer]}) {
        wait_js($p, 'leqra.getState().phase==="playing"');
        main::track($p);
    }
    $req = HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/cannon39'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'shield' => JSON::PP::true})));
    $r = request_ok($req);
    $setup = decode_json($r->content);
    for $p (@{[$host, $guest, $viewer]}) {
        wait_js($p, 'gen=>__test.online.generation===gen&&__test.online.snapshots.at(-1).tanks.every(t=>t.power===\'cannon\')', $setup->{'generation'}, {});
    }
    main::check(JSON::PP::true, 'All live clients receive server Cannon grants and the same covered arena');
    wait_js($host, 'document.querySelector(\'#weaponLabel\').textContent.includes(\'CANNON\') && document.querySelector(\'#weaponLabel2\').textContent.includes(\'CANNON\')');
    main::check(JSON::PP::true, 'Both local online pilots have independent Cannon HUDs');
    $host->bringToFront();
    $host->keyboard()->down('f');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(70));
    $host->keyboard()->up('f');
    wait_js($guest, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).shield===0', $gid, {});
    main::check(evaluate_js($guest, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).alive', $gid), 'Remote tank survives Cannon hit behind two walls because its shield absorbs it');
    for my $item (@{[[$host, 'Host'], [$guest, 'Remote player'], [$viewer, 'Phone spectator']]}) {
        my $tuple_46_6 = $item;
        my $p = $tuple_46_6->[0];
        my $label = $tuple_46_6->[1];
        my $seen = main::cannon_seen($p, $hid);
        main::check((do { my $boolean_value = (($seen->{'count'} > 0)); truth_value($boolean_value) ? do { my $boolean_value = $seen->{'correct'}; truth_value($boolean_value) ? $seen->{'crossed'} : $boolean_value } : $boolean_value }), ($label . ' sees true-size/speed Cannon cross both walls without a bounce'));
    }
    main::check(evaluate_js($viewer, 'leqra.getState().online.spectating'), 'Viewing Cannon fire never grants a spectator a tank');
    wait_js($host, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).cooldown===0', $hid, {});
    $host->keyboard()->down('f');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(70));
    $host->keyboard()->up('f');
    wait_js($guest, 'id=>!__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).alive', $gid, {});
    main::check(JSON::PP::true, 'Second Cannon shot kills unshielded remote tank behind cover');
    wait_js($host, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).charges===1', $hid, {});
    main::check(JSON::PP::true, 'Server charges track two primary shots independently');
    $host->keyboard()->down('Space');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(70));
    $host->keyboard()->up('Space');
    wait_js($host, 'id=>wire39.some(s=>s.bullets.some(b=>b.kind===\'cannon\'&&b.owner===id&&b.x>705))', $pid, {});
    for my $item (@{[[$host, 'Host'], [$viewer, 'Spectator']]}) {
        my $tuple_57_6 = $item;
        my $p = $tuple_57_6->[0];
        my $label = $tuple_57_6->[1];
        my $seen = main::cannon_seen($p, $pid);
        main::check((do { my $boolean_value = (($seen->{'count'} > 0)); truth_value($boolean_value) ? do { my $boolean_value = $seen->{'correct'}; truth_value($boolean_value) ? $seen->{'crossed'} : $boolean_value } : $boolean_value }), ($label . ' sees Player 2 Space-fired Cannon owned by the correct tank'));
    }
    main::check(evaluate_js($host, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).charges===2', $pid), 'Player 2 consumes its own charge, not Player 1 ammo');
    $host->screenshot({path => format_value($out->child('online-cannon.png'))});
    $viewer->screenshot({path => format_value($out->child('spectator-cannon-390.png'))});
    $before = evaluate_js($host, 'leqra.getState().online.id');
    evaluate_js($host, '__test.online.socket.close(4000,"Cannon reconnect test")');
    wait_js($host, '!leqra.getState().online.connected');
    wait_js($host, 'leqra.getState().online.connected', undef, {timeout => 12000});
    main::check((value_eq(evaluate_js($host, 'leqra.getState().online.id'), $before)), 'Cannon update retains controller identity after reconnection');
    main::check(evaluate_js($host, 'id=>__test.online.snapshots.at(-1).tanks.find(t=>t.id===id).power===\'cannon\'', $pid), 'Reconnection preserves still-equipped secondary Cannon');
    main::check((!truth_value($errors)), 'No uncaught errors with server-backed Cannon gameplay');
    $out->child('results.json')->spew_utf8(json_text({'version' => '3.9.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Real Go sockets; exact assets injected with synthetic URL/storage. Deterministic grant/cover only in loopback _test.go fixture.'}, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
$b->close();
die $caught_error if $caught_error;
