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

my ($after, $args, $assets, $before, $blocked, $browser, $checks, $code, $code2, $code3, $colors, $context, $contexts, $copied, $copied_session, $different, $errors, $follower, $full, $host, $host2, $host3, $i, $invalid, $landing, $layouts, $lost, $lost_code, $lost_session, $manual_guest, $missing, $named_code, $no_storage_host, $old_id, $options, $out, $p, $page, $parser, $phone, $players, $pw, $restored, $result, $resumed, $retry, $root, $sent, $session, $stale, $stale_code, $stale_missing, $storage_code, $tiny, $typed, $typed_code, $wide);
# v2.4 room UX and join-or-create regression tests. Optional Playwright tooling only.
# Run against the app, or --isolated with TestBrowserFixture (TESTING.md).
# Isolated mode injects the shipped assets, provides a synthetic URL/storage,
# and uses real WebSockets to the test-only local Go server.
$parser = {};
$args = do { my %args = ('url' => 'http://localhost:8080', 'isolated' => undef, 'browser' => undef, 'output' => 'test-output/room-features'); my $help; GetOptions('isolated!' => \$args{'isolated'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl room_features_browser.pl url --isolated --browser --output
'; if ($help) { print 'Usage: perl room_features_browser.pl url --isolated --browser --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2)->child('web');
$assets = asset_directory($root);
$out = path($args->{'output'});
$out->mkpath;
my $tuple_25_0 = [[], []];
$checks = $tuple_25_0->[0];
$errors = $tuple_25_0->[1];
sub check {
    my ($condition, $label) = @_;
    assert_ok($condition, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
sub state {
    my ($page) = @_;
    return evaluate_js($page, 'leqra.getState()');
}
sub connected {
    my ($page) = @_;
    wait_js($page, 'leqra.getState().online?.connected', undef, {timeout => 10000});
}
sub names {
    my ($page) = @_;
    my ($p);
    return [map { my $p = $_; $p->{'name'} } @{main::state($page)->{'online'}->{'players'}}];
}
$pw = start_playwright();
my $playwright = $pw;
$options = {'headless' => JSON::PP::true};
if (truth_value($args->{'browser'})) {
    $options->{'executablePath'} = $args->{'browser'};
}
$browser = $pw->launch(type => 'chrome', %{$options});
$contexts = [];
sub load {
    my ($query, $name, $session, $size, $blocked_storage) = @_;
    my ($context, $html, $js, $local, $mobile, $page, $pos, $setup, $tab, $url);
    $query //= '';
    $name //= undef;
    $session //= undef;
    $size //= [1365, 950];
    $blocked_storage //= JSON::PP::false;
    $mobile = (do { my $boolean_value = (($size->[0] < 760)); truth_value($boolean_value) ? $boolean_value : (($size->[1] < 620)) });
    $context = $browser->newContext({viewport => {'width' => $size->[0], 'height' => $size->[1]}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    push(@{$contexts}, $context);
    $page = $context->newPage();
    capture_event($page, 'pageerror', $errors, '(e) => String(e)');
    $url = ((trim_text($args->{'url'}, '/', 'rstrip') . '/') . $query);
    $setup = 'window.__sockets=[];window.__sent=[];window.__messages=[];
const RealSocket=window.WebSocket;
window.WebSocket=class extends RealSocket{
 constructor(...a){super(...a);window.__sockets.push(this);this.addEventListener(\'message\',e=>window.__messages.push(JSON.parse(e.data)))}
 send(value){window.__sent.push(JSON.parse(value));return super.send(value)}
};';
    if (truth_value($args->{'isolated'})) {
        $setup .= '
function memoryStorage(initial){const data={...initial};return {
 getItem:k=>Object.prototype.hasOwnProperty.call(data,k)?data[k]:null,
 setItem:(k,v)=>{data[k]=String(v)}, removeItem:k=>{delete data[k]},clear:()=>{for(const k in data)delete data[k]}
};}
';
        $local = (truth_value((defined($name))) ? {'leqra.name' => $name} : {});
        $tab = (truth_value($session) ? {'leqra.session' => json_text($session)} : {});
        $setup .= ('Object.defineProperty(window,\'localStorage\',{configurable:true,value:memoryStorage(' . json_text($local) . ')});');
        $setup .= ('Object.defineProperty(window,\'sessionStorage\',{configurable:true,value:memoryStorage(' . json_text($tab) . ')});');
        if (truth_value($blocked_storage)) {
            $setup .= 'for(const storage of [localStorage,sessionStorage])for(const key of [\'getItem\',\'setItem\',\'removeItem\'])storage[key]=()=>{throw new Error(\'Storage disabled by test\')};';
        }
        $html = $root->child('index.html')->slurp_utf8;
        $html = replace_re('<link[^>]*>', '', $html);
        $html = replace_text(replace_text($html, '<script src="game.js" defer></script>', ''), '<script src="netcode.js" defer></script>', '');
        $html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
        $page->setContent($html);
        evaluate_js($page, (('()=>{' . $setup) . '}'));
        $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
        $pos = rindex($js, '})()');
        $js = ((substr($js, 0, $pos - 0) . ('})(new URL(' . json_text($url) . '));')) . substr($js, ($pos + 4)));
        $page->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
        $page->addScriptTag({content => $js});
    } else {
        if (truth_value((defined($name)))) {
            $setup .= ('localStorage.setItem(\'leqra.name\',' . json_text($name) . ');');
        }
        if (truth_value($session)) {
            $setup .= ('sessionStorage.setItem(\'leqra.session\',' . json_text(json_text($session)) . ');');
        }
        if (truth_value($blocked_storage)) {
            $setup .= 'for(const key of [\'getItem\',\'setItem\',\'removeItem\'])Storage.prototype[key]=()=>{throw new Error(\'Storage disabled by test\')};';
        }
        $page->addInitScript($setup);
        $page->goto($url);
    }
    wait_js($page, 'window.leqra');
    return $page;
}
sub own_name {
    my ($page, $expected) = @_;
    wait_js($page, 'name=>leqra.getState().online?.players.some(p=>p.id===leqra.getState().online.id&&p.name===name)', $expected, {});
}
sub rename {
    my ($page, $value, $prefix, $enter) = @_;
    $prefix //= 'room';
    $enter //= JSON::PP::false;
    $page->locator(('#' . $prefix . 'Callsign'))->fill($value);
    if (truth_value($enter)) {
        $page->locator(('#' . $prefix . 'Callsign'))->press('Enter');
    } else {
        $page->locator(('#' . $prefix . 'CallsignForm button'))->click();
    }
}
sub create {
    my ($name) = @_;
    my ($page);
    $name //= 'HOST';
    $page = main::load(undef, $name, undef, undef, undef);
    $page->locator('[data-mode=online]')->click();
    $page->locator('#createRoomBtn')->click();
    main::connected($page);
    return [$page, main::state($page)->{'online'}->{'code'}];
}
my $tuple_122_4 = main::create();
$host = $tuple_122_4->[0];
$code = $tuple_122_4->[1];
$before = main::state($host)->{'online'};
main::rename($host, 'HOST NEW');
main::own_name($host, 'HOST NEW');
main::check((do { my $boolean_value = (value_eq(main::state($host)->{'online'}->{'id'}, $before->{'id'})); truth_value($boolean_value) ? (value_eq(main::state($host)->{'online'}->{'code'}, $code)) : $boolean_value }), 'Lobby rename preserves seat and room');
main::check((value_eq(evaluate_js($host, 'localStorage.getItem(\'leqra.name\')'), 'HOST NEW')), 'Server-approved callsign saved on device');
main::check((value_eq(evaluate_js($host, 'JSON.parse(sessionStorage.getItem(\'leqra.session\')).name'), 'HOST NEW')), 'Reconnect storage uses renamed callsign');
$layouts = [[1365, 950], [390, 844], [320, 568], [844, 390]];
$phone = main::load(('?room=' . lc($code)), 'RAIN', undef, $layouts->[1], undef);
main::connected($phone);
$tiny = main::load(('?room=' . $code), undef, undef, $layouts->[2], undef);
main::connected($tiny);
$wide = main::load(('?room=' . $code), 'WIDE', undef, $layouts->[3], undef);
main::connected($wide);
$players = [$host, $phone, $tiny, $wide];
main::own_name($phone, 'RAIN');
main::own_name($tiny, 'PILOT');
main::check((do { my $boolean_value = $phone->locator('#roomScreen')->isVisible(); truth_value($boolean_value) ? (contains_value(main::names($phone), 'RAIN')) : $boolean_value }), 'Lowercase invite automatically joins with saved callsign');
main::check((do { my $boolean_value = $tiny->locator('#roomScreen')->isVisible(); truth_value($boolean_value) ? (contains_value(main::names($tiny), 'PILOT')) : $boolean_value }), 'New visitor joins invite directly as PILOT');
main::check(!scalar(grep { my $p = $_; !((value_eq(evaluate_js($p, '__sent.filter(m=>m.type==="join").length'), 1))) } @{array_slice($players, 1, undef)}), 'Invite opens exactly one joining connection per fresh visitor');
for my $item (@{[map { [$_, $players->[$_]] } 0 .. $#{$players}]}) {
    my $tuple_140_8 = $item;
    my $i = $tuple_140_8->[0];
    my $page = $tuple_140_8->[1];
    wait_js($page, 'leqra.getState().online.players.length===4');
    main::check((contains_value(main::names($page), 'HOST NEW')), ('Renamed host visible to client ' . ($i + 1)));
    main::check(evaluate_js($page, 'document.documentElement.scrollWidth<=innerWidth'), ('No horizontal overflow ' . $layouts->[$i]));
    my $colors = evaluate_js($page, '[\'createRoomBtn\',\'joinRoomBtn\'].map(id=>{const s=getComputedStyle(document.getElementById(id));return [s.backgroundColor,s.color,s.borderTopColor]})');
    main::check((value_eq($colors->[0], $colors->[1])), ('Join and Create Room share colors ' . $layouts->[$i]));
    main::check(evaluate_js($page->locator('#startRoomBtn'), 'e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1'), ('Room start action fits vertically ' . $layouts->[$i]));
    $page->screenshot({path => format_value($out->child(('room-' . $layouts->[$i]->[0] . 'x' . $layouts->[$i]->[1] . '.png')))});
}
$phone->locator('#roomCallsign')->fill('DRAFT NAME');
$host->locator('#readyBtn')->click();
wait_js($phone, 'leqra.getState().online.players[0].ready');
main::check((value_eq($phone->locator('#roomCallsign')->inputValue(), 'DRAFT NAME')), 'Ready update does not clobber callsign draft');
main::rename($phone, '  Rain Fox  ', undef, JSON::PP::true);
main::own_name($phone, 'Rain Fox');
wait_js($host, 'leqra.getState().online.players.some(p=>p.name==="Rain Fox")');
main::check((contains_value(main::names($host), 'Rain Fox')), 'Enter saves callsign and broadcasts to other pilots');
main::rename($phone, '<>😈');
wait_js($phone, 'document.getElementById("roomCallsignStatus").classList.contains("error")');
main::check((contains_value(main::names($phone), 'Rain Fox')), 'Invalid rename shows error and preserves previous name');
main::check(main::state($phone)->{'online'}->{'connected'}, 'Invalid callsign does not disconnect pilot');
main::rename($phone, 'RAIN AGAIN');
main::own_name($phone, 'RAIN AGAIN');
main::check((value_eq($phone->locator('#roomCallsign')->inputValue(), 'RAIN AGAIN')), 'Callsign can be changed repeatedly');
$full = main::load(('?room=' . $code));
wait_js($full, 'document.getElementById("netStatus").classList.contains("error")');
main::check((contains_value(lc($full->locator('#netStatus')->innerText()), 'seats')), 'Full invite returns useful error without manual join step');
main::check((value_eq(evaluate_js($full, '__sent.filter(m=>m.type==="join").length'), 1)), 'Full room does not trigger endless auto-join retries');
$full->close();
for $page (@{array_slice($players, 1, undef)}) {
    $page->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $page (@{$players}) {
    wait_js($page, 'leqra.getState().phase==="playing"');
}
$host->locator('#pauseBtn')->click();
$before = main::state($host);
main::rename($host, 'Fierce Falcon', 'menu', JSON::PP::true);
main::own_name($host, 'Fierce Falcon');
wait_js($phone, 'leqra.getState().tanks.some(t=>t.name==="Fierce Falcon")');
$after = main::state($host);
main::check((($after->{'online'}->{'serverTick'} > $before->{'online'}->{'serverTick'})), 'Match keeps advancing while editing callsign');
main::check((do { my $boolean_value = (value_eq($after->{'online'}->{'id'}, $before->{'online'}->{'id'})); truth_value($boolean_value) ? (value_eq($after->{'scores'}, $before->{'scores'})) : $boolean_value }), 'In-match rename preserves tank identity and score');
main::check((contains_value(main::names($phone), 'Fierce Falcon')), 'In-match rename reaches remote room and tank labels');
$host->screenshot({path => format_value($out->child('in-match-callsign.png'))});
$host->locator('#onlineReturnBtn')->click();
$session = evaluate_js($wide, 'JSON.parse(sessionStorage.getItem(\'leqra.session\'))');
$old_id = main::state($wide)->{'online'}->{'id'};
$wide->close();
wait_js($host, 'id=>leqra.getState().online.players.some(p=>p.id===id&&!p.connected)', $old_id, {});
$resumed = main::load(('?room=' . $code), 'STALE LOCAL', $session, $layouts->[3], undef);
main::connected($resumed);
main::check((do { my $boolean_value = (value_eq(main::state($resumed)->{'online'}->{'id'}, $old_id)); truth_value($boolean_value) ? (value_eq(scalar(@{main::names($resumed)}), 4)) : $boolean_value }), 'Invite with live reconnect credential resumes seat instead of duplicating it');
main::check((value_eq($resumed->locator('#menuCallsign')->inputValue(), 'WIDE')), 'Resume restores authoritative name over stale local name');
$resumed->locator('#pauseBtn')->click();
main::rename($resumed, 'WIDE NEW', 'menu', undef);
main::own_name($resumed, 'WIDE NEW');
main::check(evaluate_js($resumed->locator('#onlineLeaveBtn'), 'e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1'), 'Landscape match menu keeps Leave room visible after saving');
$resumed->screenshot({path => format_value($out->child('landscape-callsign-menu.png'))});
main::check((value_eq($resumed->locator('#menuCallsignForm button')->isEnabled(), JSON::PP::false)), 'Saved callsign disables redundant Save action');
my $tuple_202_4 = main::create('SECOND HOST');
$host2 = $tuple_202_4->[0];
$code2 = $tuple_202_4->[1];
$stale = {'code' => $code2, 'token' => 'expired-token', 'name' => 'STALE PILOT', 'at' => int((time() * 1000))};
$retry = main::load(('?room=' . $code2), undef, $stale, undef, undef);
main::connected($retry);
main::check((contains_value(main::names($retry), 'STALE PILOT')), 'Expired invite resume token falls back to a fresh seat');
$sent = evaluate_js($retry, '__sent.filter(m=>m.type==="join")');
main::check((do { my $boolean_value = (value_eq(scalar(@{$sent}), 2)); truth_value($boolean_value) ? do { my $boolean_value = (contains_value($sent->[0], 'token')); truth_value($boolean_value) ? (!(contains_value($sent->[1], 'token'))) : $boolean_value } : $boolean_value }), 'Expired-token fallback uses one fresh join, not a reconnect loop');
$copied_session = evaluate_js($retry, 'JSON.parse(sessionStorage.getItem(\'leqra.session\'))');
$copied = main::load(('?room=' . $code2), undef, $copied_session, undef, undef);
main::connected($copied);
main::check((do { my $boolean_value = (!value_eq(main::state($copied)->{'online'}->{'id'}, main::state($retry)->{'online'}->{'id'})); truth_value($boolean_value) ? main::state($retry)->{'online'}->{'connected'} : $boolean_value }), 'Copied-tab invitation joins separately without replacing active pilot');
$different = main::load(('?room=' . $code2), 'EXPLICIT', $session, undef, undef);
main::connected($different);
main::check((do { my $boolean_value = (value_eq(main::state($different)->{'online'}->{'code'}, $code2)); truth_value($boolean_value) ? (contains_value(main::names($different), 'EXPLICIT')) : $boolean_value }), 'Explicit invite takes priority over another room saved in session');
sub fresh_code {
    my ($unused);
    return join('', @{[map { my $unused = $_; substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', int(rand(length('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'))), 1) } @{[0 .. 6 - 1]}]});
}
$named_code = main::fresh_code();
$missing = main::load(('?room=' . lc($named_code)), 'INVITE HOST', undef, undef, undef);
main::connected($missing);
main::own_name($missing, 'INVITE HOST');
main::check((value_eq(main::state($missing)->{'online'}->{'code'}, $named_code)), 'Missing invite creates exactly the requested room code');
main::check((contains_value($missing->locator('#roomCallsignForm label')->innerText(), 'HOST')), 'Missing invite makes its first pilot the host');
main::check(evaluate_js($missing, '__messages.find(m=>m.type==="welcome").created===true'), 'Creator welcome identifies newly created room');
main::check(evaluate_js($missing, '__sent.filter(m=>m.type==="join").length===1 && !__sent.some(m=>m.type==="create")'), 'Missing invite joins and creates in one request, without a random-code fallback');
main::check($missing->locator('#startRoomBtn')->isDisabled(), 'Auto-created host still needs another ready pilot');
$follower = main::load(('?room=' . $named_code), 'FOLLOWER', undef, undef, undef);
main::connected($follower);
wait_js($missing, 'leqra.getState().online.players.length===2');
main::check((do { my $boolean_value = (value_eq(main::state($follower)->{'online'}->{'code'}, $named_code)); truth_value($boolean_value) ? (!value_eq(main::state($follower)->{'online'}->{'id'}, main::state($missing)->{'online'}->{'id'})) : $boolean_value }), 'Next visitor joins the same room as a guest');
main::check((do { my $boolean_value = (contains_value($missing->locator('#roomCallsignForm label')->innerText(), 'HOST')); truth_value($boolean_value) ? (!(contains_value($follower->locator('#roomCallsignForm label')->innerText(), 'HOST'))) : $boolean_value }), 'Existing-room invite preserves the original host');
main::check(evaluate_js($follower, '__messages.find(m=>m.type==="welcome").created===false'), 'Existing-room visitor does not report another creation');
main::check((value_eq($missing->locator('#roomRoster [data-kick-target]')->count(), 1)), 'Automatically assigned host receives kick controls');
$missing->locator('#readyBtn')->click();
$follower->locator('#readyBtn')->click();
wait_js($missing, '!document.querySelector("#startRoomBtn").disabled');
$missing->locator('#startRoomBtn')->click();
wait_js($follower, 'leqra.getState().phase==="playing"');
main::check((value_eq(main::state($missing)->{'phase'}, 'playing')), 'Auto-created room starts a normal server-authoritative match');
$typed_code = main::fresh_code();
$typed = main::load(undef, 'TYPED HOST', undef, $layouts->[2], undef);
$typed->locator('[data-mode=online]')->click();
$typed->locator('#joinCode')->fill(lc($typed_code));
$typed->locator('#joinCode')->press('Enter');
main::connected($typed);
main::own_name($typed, 'TYPED HOST');
main::check((do { my $boolean_value = (value_eq(main::state($typed)->{'online'}->{'code'}, $typed_code)); truth_value($boolean_value) ? (contains_value($typed->locator('#roomCallsignForm label')->innerText(), 'HOST')) : $boolean_value }), 'Typing a missing code and pressing Enter creates a room and assigns host');
main::check((do { my $boolean_value = $typed->locator('#roomScreen')->isVisible(); truth_value($boolean_value) ? evaluate_js($typed->locator('#leaveRoomBtn'), 'e=>e.getBoundingClientRect().bottom<=document.getElementById("arenaWrap").getBoundingClientRect().bottom+1') : $boolean_value }), 'Created room controls fit a 320x568 phone');
$typed->screenshot({path => format_value($out->child('created-room-320x568.png'))});
$manual_guest = main::load(undef, 'MANUAL GUEST', undef, $layouts->[3], undef);
$manual_guest->locator('[data-mode=online]')->click();
$manual_guest->locator('#joinCode')->fill($typed_code);
$manual_guest->locator('#joinRoomBtn')->click();
main::connected($manual_guest);
main::own_name($manual_guest, 'MANUAL GUEST');
main::check((do { my $boolean_value = (value_eq(main::state($manual_guest)->{'online'}->{'code'}, $typed_code)); truth_value($boolean_value) ? (!(contains_value($manual_guest->locator('#roomCallsignForm label')->innerText(), 'HOST'))) : $boolean_value }), 'Join button joins an existing named room without taking host');
$stale_code = main::fresh_code();
$stale_missing = {'code' => $stale_code, 'token' => 'old-missing-credential', 'name' => 'RETURNING HOST', 'at' => int((time() * 1000))};
$restored = main::load(('?room=' . $stale_code), undef, $stale_missing, $layouts->[1], undef);
main::connected($restored);
main::own_name($restored, 'RETURNING HOST');
$sent = evaluate_js($restored, '__sent.filter(m=>m.type==="join")');
main::check((do { my $boolean_value = (value_eq(scalar(@{$sent}), 2)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq(($sent->[0]->{'token'} // undef), $stale_missing->{'token'})); truth_value($boolean_value) ? (!(contains_value($sent->[1], 'token'))) : $boolean_value } : $boolean_value }), 'Invite to deleted room retries once as a fresh join after stale resume');
main::check((do { my $boolean_value = (value_eq(main::state($restored)->{'online'}->{'code'}, $stale_code)); truth_value($boolean_value) ? (contains_value($restored->locator('#roomCallsignForm label')->innerText(), 'HOST')) : $boolean_value }), 'Stale-session invite creates missing room and makes visitor host');
main::check((!value_eq(evaluate_js($restored, 'JSON.parse(sessionStorage.getItem("leqra.session")).token'), $stale_missing->{'token'})), 'Recreated room allocates fresh credentials instead of reusing expired identity');
$lost_code = main::fresh_code();
$lost_session = {'code' => $lost_code, 'token' => 'background-reconnect-only', 'name' => 'LOST PILOT', 'at' => int((time() * 1000))};
$lost = main::load(undef, undef, $lost_session, undef, undef);
wait_js($lost, 'document.getElementById("netStatus").classList.contains("error")');
main::check((do { my $boolean_value = (!truth_value(main::state($lost)->{'online'}->{'connected'})); truth_value($boolean_value) ? (value_eq(evaluate_js($lost, '__sent.filter(m=>m.type==="join").length'), 1)) : $boolean_value }), 'Background resume alone does not resurrect a missing room or start a join loop');
$lost->locator('#joinCode')->fill($lost_code);
$lost->locator('#joinRoomBtn')->click();
main::connected($lost);
main::own_name($lost, 'LOST PILOT');
main::check((contains_value($lost->locator('#roomCallsignForm label')->innerText(), 'HOST')), 'Explicit Join after a failed background resume creates the requested room');
$storage_code = main::fresh_code();
$no_storage_host = main::load(('?room=' . $storage_code), undef, undef, $layouts->[1], JSON::PP::true);
main::connected($no_storage_host);
main::own_name($no_storage_host, 'PILOT');
main::check((do { my $boolean_value = (value_eq(main::state($no_storage_host)->{'online'}->{'code'}, $storage_code)); truth_value($boolean_value) ? (contains_value($no_storage_host->locator('#roomCallsignForm label')->innerText(), 'HOST')) : $boolean_value }), 'Missing-room invitation creates a host even with browser storage blocked');
$invalid = main::load('?room=bad%00name');
main::check((do { my $boolean_value = $invalid->locator('#onlineScreen')->isVisible(); truth_value($boolean_value) ? (value_eq(evaluate_js($invalid, '__sockets.length'), 0)) : $boolean_value }), 'Malformed invite opens error screen without contacting server');
main::check((contains_value($invalid->locator('#netStatus')->innerText(), '1–128')), 'Malformed invite explains how to recover');
my $tuple_281_4 = main::create('STORAGE HOST');
$host3 = $tuple_281_4->[0];
$code3 = $tuple_281_4->[1];
$blocked = main::load(('?room=' . $code3), undef, undef, $layouts->[1], JSON::PP::true);
main::connected($blocked);
main::check((contains_value(main::names($blocked), 'PILOT')), 'Invite works when browser storage is unavailable');
main::rename($blocked, 'NO STORAGE');
main::own_name($blocked, 'NO STORAGE');
main::check((contains_value(main::names($blocked), 'NO STORAGE')), 'Renaming still works with storage disabled');
$landing = main::load(undef, 'RETURNING', undef, undef, undef);
main::check((do { my $boolean_value = (value_eq(main::state($landing)->{'phase'}, 'menu')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq(main::state($landing)->{'mode'}, 'solo')); truth_value($boolean_value) ? (value_eq(evaluate_js($landing, '__sockets.length'), 0)) : $boolean_value } : $boolean_value }), 'Ordinary link does not auto-join or auto-create a room');
main::check((!truth_value($errors)), 'No JavaScript runtime errors in room feature flows');
$result = {'checks_passed' => scalar(@{$checks}), 'checks' => $checks, 'javascript_errors' => $errors, 'browser_version' => $browser->version(), 'isolated_assets' => $args->{'isolated'}, 'layouts' => $layouts, 'version' => evaluate_js($landing, 'leqra.version')};
$out->child('room-features-results.json')->spew_utf8(json_text($result, 1));
print(join(" ", json_text($result, 1)), "\n");
for $context (@{$contexts}) {
    $context->close();
}
$browser->close();
