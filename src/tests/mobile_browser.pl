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

my ($args, $browser, $device, $errors, $parser, $playwright, $url);
# Run mobile integration checks on a dedicated local leqra server.
# 
# Usage: perl src/tests/mobile_browser.pl [URL] [--engine chromium|webkit]
sub load {
    my ($context, $url, $name, $errors) = @_;
    my ($page, $tour);
    $page = $context->newPage();
    capture_event($page, 'pageerror', $errors, '(error) => String(error)');
    $page->addInitScript(('localStorage.setItem(\'leqra.name\', ' . json_text($name) . ')'));
    $page->goto($url);
    wait_js($page, '() => window.leqra && window.leqraInfinity');
    assert_ok(evaluate_js($page, 'leqra.getState().touchUI'), 'page.evaluate("leqra.getState().touchUI")');
    $tour = $page->locator('#introTourDialog');
    if (truth_value($tour->isVisible())) {
        $page->locator('#introTourSkip')->tap();
        expect_locator($tour, 'to_be_hidden');
    }
    return $page;
}
sub choose_mode {
    my ($page, $mode) = @_;
    my ($choice, $settings);
    $settings = $page->locator('#roomSettings');
    if (truth_value((!defined($settings->getAttribute('open'))))) {
        $settings->locator('summary')->tap();
    }
    $choice = $settings->locator(('[data-room-mode="' . $mode . '"]'));
    $choice->tap();
    expect_locator($choice, 'to_have_attribute', 'aria-checked', 'true');
    $settings->locator('summary')->tap();
}
sub require_on_screen {
    my ($page, @selectors) = @_;
    my $options = ref($selectors[-1]) eq 'HASH' ? pop @selectors : {};
    my $minimum_size = $options->{minimum_size} // 40;
    my $selectors = \@selectors;
    my ($box, $selector, $viewport);
    $viewport = evaluate_js($page, '() => ({
        width: visualViewport.width, height: visualViewport.height,
        x: visualViewport.offsetLeft, y: visualViewport.offsetTop
    })');
    for $selector (@{$selectors}) {
        $box = $page->locator($selector)->boundingBox();
        assert_ok((do { my $boolean_value = $box; truth_value($boolean_value) ? do { my $boolean_value = (($box->{'width'} >= $minimum_size)); truth_value($boolean_value) ? (($box->{'height'} >= $minimum_size)) : $boolean_value } : $boolean_value }), [$selector, $box]);
        assert_ok((($box->{'x'} >= ($viewport->{'x'} - 1))), [$selector, $box, $viewport]);
        assert_ok((($box->{'y'} >= ($viewport->{'y'} - 1))), [$selector, $box, $viewport]);
        assert_ok(((($box->{'x'} + $box->{'width'}) <= (($viewport->{'x'} + $viewport->{'width'}) + 1))), [$selector, $box, $viewport]);
        assert_ok(((($box->{'y'} + $box->{'height'}) <= (($viewport->{'y'} + $viewport->{'height'}) + 1))), [$selector, $box, $viewport]);
    }
}
sub hold_joystick {
    my ($page, $selector, $pointer_type) = @_;
    my ($base, $zone);
    $zone = $page->locator($selector);
    $base = $zone->locator('.stick-base')->boundingBox();
    $zone->dispatchEvent('pointerdown', {'pointerId' => 7, 'pointerType' => $pointer_type, 'button' => 0, 'buttons' => 1, 'clientX' => ($base->{'x'} + ($base->{'width'} * 0.9)), 'clientY' => ($base->{'y'} + ($base->{'height'} * 0.5))});
}
sub release_joystick {
    my ($page, $selector, $pointer_type) = @_;
    $page->locator($selector)->dispatchEvent('pointerup', {'pointerId' => 7, 'pointerType' => $pointer_type, 'button' => 0, 'buttons' => 0});
}
sub play_offline {
    my ($browser, $device, $url, $errors) = @_;
    my ($arena, $context, $controls, $mode, $page, $pause);
    $context = $browser->newContext({%{$device}});
    $page = main::load($context, ($url . '?test=1'), 'MOBILE LOCAL', $errors);
    wait_js($page, '() => !!navigator.serviceWorker.controller');
    $context->setOffline(JSON::PP::true);
    $page->reload();
    wait_js($page, '() => !!window.leqraInfinity');
    for $mode (@{['elimination', 'ctf', 'koth', 'survival']}) {
        main::choose_mode($page, $mode);
        $page->locator('#startRoomBtn')->tap();
        wait_js($page, '() => leqra.getState().phase === \'playing\'');
        assert_ok((value_eq(evaluate_js($page, 'leqra.getState().rules.mode'), $mode)), 'page.evaluate("leqra.getState().rules.mode") == mode');
        main::require_on_screen($page, '#arena', '#stickZone', '#fireBtn');
        if (truth_value((value_eq($mode, 'elimination')))) {
            $page->locator('#fireBtn')->tap();
            wait_js($page, '() => __test.bullets.some(b => b.owner === 0)');
            $page->setViewportSize({'width' => 568, 'height' => 320});
            wait_js($page, '() => leqra.getState().touchLandscape');
            main::require_on_screen($page, '#arena', '#stickZone', '#fireBtn');
            $page->setViewportSize($device->{'viewport'});
            wait_js($page, '() => !leqra.getState().touchLandscape');
        }
        $page->reload();
        wait_js($page, '() => !!window.leqra');
    }
    main::choose_mode($page, 'infinity');
    $page->locator('#startRoomBtn')->tap();
    $arena = $page->locator('#infiniteArena');
    expect_locator($arena, 'to_have_attribute', 'data-mode', 'offline');
    expect_locator($page->locator('#infiniteStatus'), 'to_be_hidden');
    expect_locator($page->locator('#infiniteHeader > #gameHeader'), 'to_be_visible');
    main::require_on_screen($page, '#infiniteCanvas', '#infiniteStick', '#infiniteFire');
    main::require_on_screen($page, '#pauseBtn', {'minimum_size' => 30});
    $page->setViewportSize({'width' => 568, 'height' => 320});
    wait_js($page, '() => leqra.getState().touchLandscape');
    main::require_on_screen($page, '#infiniteCanvas', '#infiniteStick', '#infiniteFire');
    main::require_on_screen($page, '#pauseBtn', {'minimum_size' => 30});
    $page->locator('#infiniteScoreboardBtn')->tap();
    expect_locator($page->locator('#infiniteLeaderboard'), 'to_contain_text', 'MOBILE LOCAL (P1)');
    $page->locator('#pauseBtn')->tap();
    $pause = $page->locator('#infinitePauseMenu');
    expect_locator($pause, 'to_be_visible');
    expect_locator($pause->getByRole('button', {name => 'BACK TO THE BATTLE', exact => JSON::PP::true}), 'to_be_visible');
    main::require_on_screen($page, '#infiniteResumeBtn', '#infiniteControlsBtn', '#infiniteExit');
    $page->locator('#infiniteControlsBtn')->tap();
    $controls = $page->locator('#controlsDialog');
    expect_locator($controls, 'to_be_visible');
    $controls->getByRole('button', {name => 'Close controls'})->tap();
    expect_locator($controls, 'to_be_hidden');
    expect_locator($pause, 'to_be_visible');
    $page->locator('#infiniteResumeBtn')->tap();
    expect_locator($pause, 'to_be_hidden');
    $page->locator('#pauseBtn')->tap();
    $page->locator('#infiniteExit')->tap();
    expect_locator($arena, 'to_be_hidden');
    expect_locator($page->locator('.app > #gameHeader'), 'to_be_visible');
    $context->close();
    print(join(" ", 'PASS installed offline app, all five modes, touch Fire, and landscape pause controls'), "\n");
}
sub play_shared_room {
    my ($browser, $device, $url, $errors) = @_;
    my ($first, $guest, $host, $page, $room, $seat, $second);
    $first = $browser->newContext({%{$device}});
    $second = $browser->newContext({%{$device}});
    $host = main::load($first, ($url . '?test=1'), 'MOBILE HOST', $errors);
    main::choose_mode($host, 'elimination');
    $host->locator('#copyInviteBtn')->tap();
    wait_js($host, '() => !!leqra.getState().online?.connected');
    $room = evaluate_js($host, 'leqra.getState().online.code');
    $guest = main::load($second, (($url . '?test=1&room=') . uri_escape_utf8($room)), 'MOBILE GUEST', $errors);
    $guest->locator('#pilotName')->fill('MOBILE GUEST');
    $guest->locator('#joinRoomBtn')->tap();
    wait_js($guest, '() => !!leqra.getState().online?.connected');
    expect_locator($host->locator('#startRoomBtn'), 'to_be_disabled');
    $guest->locator('#readyBtn')->tap();
    expect_locator($host->locator('#startRoomBtn'), 'to_be_enabled');
    $host->locator('#startRoomBtn')->tap();
    for $page (@{[$host, $guest]}) {
        wait_js($page, '() => leqra.getState().phase === \'playing\'');
        main::require_on_screen($page, '#arena', '#stickZone', '#fireBtn');
    }
    main::hold_joystick($guest, '#stickZone', 'touch');
    wait_js($guest, '() => __test.onlineControls().touchAim === true');
    main::release_joystick($guest, '#stickZone', 'touch');
    assert_ok(evaluate_js($guest, '() => !__test.onlineControls().touchAim'), 'guest.evaluate("() => !__test.onlineControls().touchAim")');
    $guest->locator('#fireBtn')->tap();
    wait_js($guest, '() => {
            const self = __test.online.id;
            return __test.online.snapshots.at(-1)?.tankMap.get(self)?.shotSerial > 0;
        }');
    $seat = evaluate_js($guest, '__test.online.id');
    evaluate_js($guest, '() => { window.testSocket = __test.online.socket; testSocket.close(4000, \'test reconnect\'); }');
    wait_js($guest, '() => leqra.getState().online?.connected &&
            __test.online.socket !== window.testSocket && leqra.getState().phase === \'playing\'');
    assert_ok((value_eq(evaluate_js($guest, '__test.online.id'), $seat)), 'guest.evaluate("__test.online.id") == seat');
    $second->close();
    $first->close();
    print(join(" ", 'PASS two touch clients ready, fire on the server, and resume the same seat'), "\n");
}
sub play_public_infinity {
    my ($browser, $device, $url, $errors) = @_;
    my ($context, $first_packet, $frame, $headers, $inputs, $messages, $name, $packet, $page, $pause, $pointer_type, $session, $upgrades, $value);
    $context = $browser->newContext({%{$device}});
    $page = main::load($context, $url, 'MOBILE PUBLIC', $errors);
    expect_locator($page->locator('#infinityToggle'), 'to_be_checked');
    $messages = [];
    capture_socket_event($page, 'websocket', 'framesent', $messages, '(frame) => frame');
    $upgrades = [];
    if (truth_value((value_eq($browser->browserType()->name(), 'chromium')))) {
        $session = $context->newCDPSession($page);
        $session->send('Network.enable');
        capture_event($session, 'Network.webSocketHandshakeResponseReceived', $upgrades, '(event) => event["response"]["headers"]');
    }
    $page->locator('#startRoomBtn')->tap();
    expect_locator($page->locator('#infiniteStatus'), 'to_contain_text', '1 online');
    if (truth_value((value_eq($browser->browserType()->name(), 'chromium')))) {
        assert_ok(scalar(grep { $_ } @{[map { my $headers = $_; map { my ($name, $value) = @{$_}; truth_value((value_eq(lc($name), 'sec-websocket-extensions'))) ? ((contains_value($value, 'permessage-deflate'))) : () } @{[map { [$_, $headers->{$_}] } keys %{$headers}]} } @{$upgrades}]}), $upgrades);
    }
    main::require_on_screen($page, '#infiniteCanvas', '#infiniteStick', '#infiniteFire');
    for $pointer_type (@{['touch', 'mouse']}) {
        $first_packet = scalar(@{$messages});
        main::hold_joystick($page, '#infiniteStick', $pointer_type);
        main::release_joystick($page, '#infiniteStick', $pointer_type);
        $inputs = [map { my $frame = $_; truth_value((!ref($frame))) ? (decode_json($frame)) : () } @{array_slice($messages, $first_packet, undef)}];
        assert_ok(scalar(grep { my $packet = $_; (do { my $boolean_value = ((($packet->{'stickX'} // 0) > 0.5)); truth_value($boolean_value) ? (value_eq(!!(truth_value(($packet->{'touchAim'} // undef))), (value_eq($pointer_type, 'touch')))) : $boolean_value }) } @{$inputs}), [$pointer_type, $inputs]);
    }
    $page->locator('#infiniteFire')->tap();
    assert_ok(scalar(grep { my $frame = $_; (do { my $boolean_value = (!ref($frame)); truth_value($boolean_value) ? (value_eq((decode_json($frame)->{'fire'} // undef), JSON::PP::true)) : $boolean_value }) } @{$messages}), $messages);
    expect_locator($page->locator('#infiniteHeader > #gameHeader'), 'to_be_visible');
    $page->locator('#soundBtn')->tap();
    expect_locator($page->locator('#soundBtn'), 'to_have_attribute', 'aria-label', 'Unmute sound');
    $page->locator('#pauseBtn')->tap();
    $pause = $page->locator('#infinitePauseMenu');
    expect_locator($pause->getByRole('button', {name => 'BACK TO THE ARENA', exact => JSON::PP::true}), 'to_be_visible');
    assert_ok(scalar(grep { my $frame = $_; (do { my $boolean_value = (!ref($frame)); truth_value($boolean_value) ? (value_eq((decode_json($frame)->{'paused'} // undef), JSON::PP::true)) : $boolean_value }) } @{$messages}), $messages);
    $page->locator('#infiniteExit')->tap();
    expect_locator($page->locator('#infiniteArena'), 'to_be_hidden');
    expect_locator($page->locator('.app > #gameHeader'), 'to_be_visible');
    $context->close();
    print(join(" ", 'PASS public Infinity touch Fire, mute, and pause'), "\n");
}
unless (caller) {
    $parser = {};
    $args = do { my %args = ('url' => 'http://localhost:8080', 'engine' => 'chromium'); my $help; GetOptions('engine=s' => \$args{'engine'}, 'help|h' => \$help) or die 'Usage: perl mobile_browser.pl url --engine
'; if ($help) { print 'Usage: perl mobile_browser.pl url --engine
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; die 'invalid engine
' if defined($args{'engine'}) && !grep { value_eq($_, $args{'engine'}) } @{['chromium', 'webkit']}; \%args; };
    $url = (trim_text($args->{'url'}, '/', 'rstrip') . '/');
    $errors = [];
    $playwright = start_playwright();
    if (truth_value((value_eq($args->{'engine'}, 'webkit')))) {
        $browser = $playwright->launch(type => 'webkit');
        $device = browser_devices()->{'iPhone 13'};
    } else {
        $browser = $playwright->launch(type => 'chrome', chromiumSandbox => JSON::PP::true);
        $device = browser_devices()->{'Pixel 7'};
    }
    eval {
        main::play_offline($browser, $device, $url, $errors);
        main::play_shared_room($browser, $device, $url, $errors);
        main::play_public_infinity($browser, $device, $url, $errors);
    1;
    };
    my $caught_error = $@;
    $browser->close();
    die $caught_error if $caught_error;
    assert_ok((!truth_value($errors)), $errors);
}
