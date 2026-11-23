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

my ($a, $a_session, $after, $alpha, $area, $args, $assets, $before, $beta, $box, $browser, $checks, $code, $contexts, $count, $errors, $gamma, $guests, $h, $host, $leave, $n, $new_a, $one, $opts, $out, $page, $parser, $pw, $refresh, $report, $root, $start, $t, $tick, $w);
# Host-kick browser checks. Optional Playwright; see TESTING.md.
# --isolated loads the exact shipped assets with synthetic URL/storage into
# about:blank and uses real WebSockets to TestBrowserFixture. No production
# origin policy is weakened. Screenshots and JSON are written to --output.
$parser = {};
$args = do { my %args = ('url' => 'http://localhost:8080', 'isolated' => undef, 'browser' => undef, 'output' => 'test-output/kick'); my $help; GetOptions('isolated!' => \$args{'isolated'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl kick_browser.pl url --isolated --browser --output
'; if ($help) { print 'Usage: perl kick_browser.pl url --isolated --browser --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2)->child('web');
$assets = asset_directory($root);
$out = path($args->{'output'});
$out->mkpath;
my $tuple_22_0 = [[], []];
$checks = $tuple_22_0->[0];
$errors = $tuple_22_0->[1];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub state {
    my ($page) = @_;
    return evaluate_js($page, 'leqra.getState()');
}
sub wait_connected {
    my ($page) = @_;
    wait_js($page, 'leqra.getState().online?.connected', undef, {timeout => 10000});
}
sub wait_count {
    my ($page, $count) = @_;
    wait_js($page, 'n=>leqra.getState().online?.players.length===n', $count, {});
}
sub member {
    my ($page, $name) = @_;
    my ($p);
    return ([map { my $p = $_; truth_value((value_eq($p->{'name'}, $name))) ? ($p) : () } @{main::state($page)->{'online'}->{'players'}}]->[0] // undef);
}
sub removed {
    my ($page) = @_;
    wait_js($page, '!leqra.getState().online?.connected && document.querySelector("#netStatus").textContent.includes("removed")');
}
sub session {
    my ($page) = @_;
    return evaluate_js($page, 'JSON.parse(sessionStorage.getItem("leqra.session"))');
}
$pw = start_playwright();
my $playwright = $pw;
$opts = {'headless' => JSON::PP::true};
if (truth_value($args->{'browser'})) {
    $opts->{'executablePath'} = $args->{'browser'};
}
$browser = $pw->launch(type => 'chrome', %{$opts});
$contexts = [];
sub load {
    my ($name, $code, $size, $tab) = @_;
    my ($context, $f, $html, $js, $k, $mobile, $page, $pos, $setup, $url, $v);
    $name //= 'PILOT';
    $code //= '';
    $size //= [1365, 950];
    $tab //= undef;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $context = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile});
    push(@{$contexts}, $context);
    $page = $context->newPage();
    capture_event($page, 'pageerror', $errors, '(e) => String(e)');
    $url = ((trim_text($args->{'url'}, '/', 'rstrip') . '/?test=1') . (truth_value($code) ? ('&room=' . $code) : ''));
    $setup = 'window.__sockets=[];window.__sent=[];window.__messages=[];window.__dropKickOnce=false;
const RealSocket=window.WebSocket;
window.WebSocket=class extends RealSocket{
 constructor(...a){super(...a);window.__sockets.push(this);this.addEventListener(\'message\',e=>{
  let m;try{m=JSON.parse(e.data)}catch(_){return}window.__messages.push(m);
  if(window.__dropKickOnce && m.type===\'kicked\'){window.__dropKickOnce=false;e.stopImmediatePropagation();this.close(4000,\'Test lost kick notification\')}
 })}
 send(data){window.__sent.push(JSON.parse(data));return super.send(data)}
};';
    if (truth_value($args->{'isolated'})) {
        $setup .= 'function memoryStorage(data){return {
 getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k],clear:()=>{for(const k in data)delete data[k]}
};}';
        $setup .= ('Object.defineProperty(window,\'localStorage\',{configurable:true,value:memoryStorage(' . json_text({'leqra.name' => $name}) . ')});');
        $setup .= ('Object.defineProperty(window,\'sessionStorage\',{configurable:true,value:memoryStorage(' . json_text((do { my $boolean_value = $tab; truth_value($boolean_value) ? $boolean_value : {} })) . ')});');
        $html = replace_re('<link[^>]*>', '', $root->child('index.html')->slurp_utf8);
        for $f (@{['netcode.js', 'game.js']}) {
            $html = replace_text($html, ('<script src="' . $f . '" defer></script>'), '');
        }
        $html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
        $page->setContent($html);
        evaluate_js($page, (('()=>{' . $setup) . '}'));
        $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
        $pos = rindex($js, '})()');
        $js = ((substr($js, 0, $pos - 0) . ('})(new URL(' . json_text($url) . '));')) . substr($js, ($pos + 4)));
        $page->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
        $page->addScriptTag({content => $js});
    } else {
        $setup .= ('localStorage.setItem(\'leqra.name\',' . json_text($name) . ');');
        for my $item (@{[map { [$_, (do { my $boolean_value = $tab; truth_value($boolean_value) ? $boolean_value : {} })->{$_}] } keys %{(do { my $boolean_value = $tab; truth_value($boolean_value) ? $boolean_value : {} })}]}) {
            my $tuple_86_16 = $item;
            my $k = $tuple_86_16->[0];
            my $v = $tuple_86_16->[1];
            $setup .= ('sessionStorage.setItem(' . json_text($k) . ',' . json_text($v) . ');');
        }
        $page->addInitScript($setup);
        $page->goto($url);
    }
    wait_js($page, 'window.leqra');
    if (truth_value((do { my $boolean_value = $code; truth_value($boolean_value) ? (!truth_value(((do { my $boolean_value = $tab; truth_value($boolean_value) ? $boolean_value : {} })->{'leqra.kicked'} // undef))) : $boolean_value }))) {
        main::wait_connected($page);
    }
    return $page;
}
sub create {
    my ($name, $size) = @_;
    my ($page);
    $name //= 'HOST';
    $size //= [1365, 950];
    $page = main::load($name, undef, $size, undef);
    $page->locator('[data-mode=online]')->click();
    $page->locator('#createRoomBtn')->click();
    main::wait_connected($page);
    return [$page, main::state($page)->{'online'}->{'code'}];
}
sub kick {
    my ($page, $p, $prefix, $confirm) = @_;
    my ($roster);
    $prefix //= 'room';
    $confirm //= JSON::PP::true;
    $roster = (truth_value((value_eq($prefix, 'room'))) ? '#roomRoster' : '#menuKickRoster');
    $page->locator(($roster . ' [data-kick-target="' . $p->{'id'} . '"]'))->click();
    wait_js($page, 'document.querySelector("#kickDialog").open');
    if (truth_value($confirm)) {
        $page->locator('#confirmKickBtn')->click();
    }
}
sub close_pages {
    my ($pages) = @_;
    my ($p);
    for $p (@{$pages}) {
        $p->context()->close();
    }
}
my $tuple_102_4 = main::create();
$host = $tuple_102_4->[0];
$code = $tuple_102_4->[1];
$alpha = main::load('ALPHA', $code);
$beta = main::load('BETA', $code, [390, 844], undef);
$gamma = main::load('GAMMA', $code);
main::wait_count($host, 4);
main::check((value_eq($host->locator('#roomRoster .kick-button')->count(), 3)), 'Host sees one Kick control for each other pilot');
main::check((do { my $boolean_value = (value_eq($alpha->locator('.kick-button')->count(), 0)); truth_value($boolean_value) ? (value_eq($beta->locator('.kick-button')->count(), 0)) : $boolean_value }), 'Guests have no Kick controls');
main::check((value_eq($host->locator('#roomRoster [data-kick-target="0"]')->count(), 0)), 'Host has no self-kick control');
$a = main::member($host, 'ALPHA');
$a_session = main::session($alpha);
main::kick($host, $a, undef, JSON::PP::false);
main::check((contains_value($host->locator('#kickDescription')->innerText(), 'ALPHA')), 'Confirmation identifies the selected pilot');
main::check((value_eq(evaluate_js($host, 'document.activeElement.id'), 'cancelKickBtn')), 'Confirmation defaults keyboard focus to Cancel');
$host->keyboard()->press('Escape');
main::check((!truth_value(evaluate_js($host->locator('#kickDialog'), 'e=>e.open'))), 'Escape dismisses confirmation without toggling game menu');
main::check((value_eq(evaluate_js($host, '__sent.filter(m=>m.type==="kick").length'), 0)), 'Cancelling sends no kick request');
main::kick($host, $a, undef, JSON::PP::false);
$alpha->locator('#roomCallsign')->fill('ALPHA NEW');
$alpha->locator('#roomCallsignForm button')->click();
wait_js($host, 'document.querySelector("#kickDescription").textContent.includes("ALPHA NEW")');
main::check((value_eq(main::member($host, 'ALPHA NEW')->{'member'}, $a->{'member'})), 'Rename preserves selected seat and updates confirmation name');
$host->locator('#cancelKickBtn')->click();
$host->locator('#readyBtn')->click();
$beta->locator('#readyBtn')->click();
main::kick($host, main::member($host, 'ALPHA NEW'));
main::removed($alpha);
main::wait_count($host, 3);
main::check((do { my $boolean_value = (value_eq(main::state($alpha)->{'phase'}, 'menu')); truth_value($boolean_value) ? $alpha->locator('#onlineScreen')->isVisible() : $boolean_value }), 'Kicked pilot returns to online menu with removal message');
main::check((!defined(main::session($alpha))), 'Kicked pilot reconnect credential is cleared');
$count = evaluate_js($alpha, '__sockets.length');
evaluate_js($alpha, 'window.dispatchEvent(new Event(\'online\'));window.dispatchEvent(new Event(\'pagehide\'))');
$Leqra::Browser::HANDLE->await($alpha->waitForTimeout(1100));
main::check((do { my $boolean_value = (value_eq(evaluate_js($alpha, '__sockets.length'), $count)); truth_value($boolean_value) ? (!defined(main::session($alpha))) : $boolean_value }), 'Kick stops automatic reconnect, online-event retries, and session rewrites');
main::check((do { my $boolean_value = main::member($host, 'HOST')->{'ready'}; truth_value($boolean_value) ? main::member($host, 'BETA')->{'ready'} : $boolean_value }), 'Other pilots keep their ready status');
$refresh = main::load('ALPHA NEW', $code, undef, {'leqra.kicked' => $code});
main::check((do { my $boolean_value = (value_eq(evaluate_js($refresh, '__sockets.length'), 0)); truth_value($boolean_value) ? (contains_value($refresh->locator('#netStatus')->innerText(), 'removed')) : $boolean_value }), 'Stale invite refresh cannot auto-join a kicked tab');
$refresh->context()->close();
$alpha->locator('#joinRoomBtn')->click();
main::wait_connected($alpha);
main::wait_count($host, 4);
$new_a = main::member($host, 'ALPHA NEW');
main::check((do { my $boolean_value = (!value_eq($new_a->{'member'}, $a->{'member'})); truth_value($boolean_value) ? (!value_eq(main::session($alpha)->{'token'}, $a_session->{'token'})) : $boolean_value }), 'Manual rejoin gets a fresh identity; kick is not a permanent ban');
evaluate_js($beta, 'p=>__sockets.at(-1).send(JSON.stringify({type:"kick",target:p.id,member:p.member}))', $new_a);
wait_js($beta, '__messages.some(m=>m.type==="error" && m.action==="kick" && m.code==="not_host")');
main::check((value_eq(scalar(@{main::state($host)->{'online'}->{'players'}}), 4)), 'Server rejects forged guest kick without removing anyone');
evaluate_js($beta, 'window.__dropKickOnce=true');
main::kick($host, main::member($host, 'BETA'));
main::removed($beta);
main::wait_count($host, 3);
main::check((value_eq(evaluate_js($beta, '__sockets.length'), 2)), 'Dropped removal notice is recovered on one reconnect attempt');
main::check((value_eq(evaluate_js($beta, '__sent.filter(m=>m.type==="join"&&!m.token).length'), 1)), 'Revoked resume does not trigger invite-as-new-pilot fallback');
main::kick($host, main::member($host, 'GAMMA'), undef, JSON::PP::false);
$gamma->locator('#leaveRoomBtn')->click();
main::wait_count($host, 2);
main::check((!truth_value(evaluate_js($host->locator('#kickDialog'), 'e=>e.open'))), 'Confirmation closes when target leaves before approval');
main::check(main::state($alpha)->{'online'}->{'connected'}, 'Stale target disappearance does not remove a different pilot');
$host->screenshot({path => format_value($out->child('desktop-host-room.png'))});
main::close_pages([$host, $alpha, $beta, $gamma]);
my $tuple_153_4 = main::create('MOBILE HOST', [390, 844]);
$host = $tuple_153_4->[0];
$code = $tuple_153_4->[1];
$guests = [map { my $n = $_; main::load($n, $code) } @{['ONE', 'TWO', 'THREE']}];
main::wait_count($host, 4);
for my $item (@{[[390, 844], [320, 568], [844, 390]]}) {
    my $tuple_156_8 = $item;
    my $w = $tuple_156_8->[0];
    my $h = $tuple_156_8->[1];
    $host->setViewportSize({'width' => $w, 'height' => $h});
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(180));
    main::check(evaluate_js($host, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow in host room ' . $w . 'x' . $h));
    $host->locator('#roomRoster .kick-button')->first()->scrollIntoViewIfNeeded();
    main::check((($host->locator('#roomRoster .kick-button')->first()->boundingBox()->{'height'} >= 40)), ('Touch kick control is at least 40px tall ' . $w . 'x' . $h));
    my $area = $host->locator('#arenaWrap')->boundingBox();
    my $start = $host->locator('#startRoomBtn')->boundingBox();
    main::check((do { my $boolean_value = ((($start->{'y'} + $start->{'height'}) <= ($area->{'y'} + $area->{'height'}))); truth_value($boolean_value) ? (($start->{'y'} >= $area->{'y'})) : $boolean_value }), ('Host Start button fits unobscured within arena ' . $w . 'x' . $h));
    $host->screenshot({path => format_value($out->child(('host-room-' . $w . 'x' . $h . '.png')))});
    main::kick($host, main::member($host, 'ONE'), undef, JSON::PP::false);
    my $box = $host->locator('#kickDialog')->boundingBox();
    main::check((do { my $boolean_value = (($box->{'x'} >= 0)); truth_value($boolean_value) ? do { my $boolean_value = (($box->{'y'} >= 0)); truth_value($boolean_value) ? do { my $boolean_value = ((($box->{'x'} + $box->{'width'}) <= $w)); truth_value($boolean_value) ? ((($box->{'y'} + $box->{'height'}) <= $h)) : $boolean_value } : $boolean_value } : $boolean_value }), ('Confirmation fits mobile viewport ' . $w . 'x' . $h));
    $host->screenshot({path => format_value($out->child(('kick-confirm-' . $w . 'x' . $h . '.png')))});
    $host->locator('#cancelKickBtn')->tap();
}
$host->setViewportSize({'width' => 390, 'height' => 844});
$Leqra::Browser::HANDLE->await($host->waitForTimeout(180));
for $page (@{[@{[$host]}, @{$guests}]}) {
    $page->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $page (@{[@{[$host]}, @{$guests}]}) {
    wait_js($page, 'leqra.getState().phase==="playing"');
}
$host->locator('#pauseBtn')->tap();
$guests->[1]->locator('#pauseBtn')->click();
main::check((do { my $boolean_value = $host->locator('#hostControls')->isVisible(); truth_value($boolean_value) ? (value_eq($host->locator('#menuKickRoster .kick-button')->count(), 3)) : $boolean_value }), 'Host can manage players from the live match menu');
main::check((!truth_value($guests->[1]->locator('#hostControls')->isVisible())), 'Guest match menu hides host controls');
for my $item (@{[[390, 844], [320, 568], [844, 390]]}) {
    my $tuple_176_8 = $item;
    my $w = $tuple_176_8->[0];
    my $h = $tuple_176_8->[1];
    $host->setViewportSize({'width' => $w, 'height' => $h});
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(180));
    main::check(evaluate_js($host, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow in match menu ' . $w . 'x' . $h));
    my $area = $host->locator('#arenaWrap')->boundingBox();
    my $leave = $host->locator('#onlineLeaveBtn')->boundingBox();
    main::check((do { my $boolean_value = ((($leave->{'y'} + $leave->{'height'}) <= ($area->{'y'} + $area->{'height'}))); truth_value($boolean_value) ? (($leave->{'y'} >= $area->{'y'})) : $boolean_value }), ('Match menu actions fit unobscured within arena ' . $w . 'x' . $h));
    $host->screenshot({path => format_value($out->child(('host-match-menu-' . $w . 'x' . $h . '.png')))});
}
$one = main::member($host, 'ONE');
main::kick($host, $one, 'menu', JSON::PP::false);
$tick = main::state($host)->{'online'}->{'serverTick'};
$Leqra::Browser::HANDLE->await($host->waitForTimeout(200));
main::check(((main::state($host)->{'online'}->{'serverTick'} > $tick)), 'Kick confirmation does not block the shared simulation');
$host->locator('#confirmKickBtn')->tap();
main::removed($guests->[0]);
main::wait_count($host, 3);
wait_js($host, 'id=>leqra.getState().tanks.some(t=>t.id===id&&!t.alive)', $one->{'id'}, {});
main::check((value_eq(main::state($host)->{'phase'}, 'playing')), 'Remaining multiplayer match continues after a kick');
$host->locator('#onlineReturnBtn')->tap();
$before = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t->{'angle'}) : () } @{main::state($host)->{'tanks'}}]->[0] // undef);
$host->keyboard()->down('KeyD');
$Leqra::Browser::HANDLE->await($host->waitForTimeout(220));
$host->keyboard()->up('KeyD');
$after = ([map { my $t = $_; truth_value((value_eq($t->{'id'}, 0))) ? ($t->{'angle'}) : () } @{main::state($host)->{'tanks'}}]->[0] // undef);
main::check(((abs(($before - $after)) > 0.1)), 'Tank control still responds after closing host menu');
$host->locator('#pauseBtn')->tap();
$host->locator('#onlineLeaveBtn')->tap();
main::wait_count($guests->[1], 2);
wait_js($guests->[1], '!document.querySelector("#hostControls").hidden');
main::check((value_eq($guests->[1]->locator('#menuKickRoster .kick-button')->count(), 1)), 'Host handoff grants the new host Kick controls');
main::kick($guests->[1], main::member($guests->[1], 'THREE'), 'menu', undef);
main::removed($guests->[2]);
main::wait_count($guests->[1], 1);
main::check((index($guests->[2]->locator('#netStatus')->innerText(), 'You were removed') == 0), 'New host can remove the remaining opponent');
wait_js($guests->[1], 'leqra.getState().phase==="onlineLobby"', undef, {timeout => 6000});
main::check((!truth_value($guests->[1]->locator('#startRoomBtn')->isEnabled())), 'Last-opponent kick ends the round and leaves a one-player lobby');
main::check((!truth_value($errors)), 'No JavaScript runtime errors in kick flows');
$report = {'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'javascript_errors' => $errors, 'isolated_assets' => $args->{'isolated'}, 'browser_version' => $browser->version(), 'version' => [split('\'', [split('version:\'', $assets->child('game.js')->slurp_utf8)]->[(-1)])]->[0]};
$out->child('kick-results.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text($report, 1)), "\n");
$browser->close();
