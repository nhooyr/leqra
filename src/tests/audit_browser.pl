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

my ($browser, $errors, $parser, $playwright, $url);
# Check room setup, roster focus, chat IME and matchmaking in Chromium.
# 
# Start a dedicated leqra server with `go run ./src`, then run
# `perl src/tests/audit_browser.pl [http://localhost:8080]`.
# Install Playwright and its Chromium browser first.
sub load_room {
    my ($context, $url, $errors) = @_;
    my ($page);
    $page = $context->newPage();
    capture_event($page, 'pageerror', $errors, '(error) => String(error)');
    $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\', \'1\')');
    $page->goto($url);
    wait_js($page, '() => !!window.leqra');
    return $page;
}
sub open_details {
    my ($page, $element_id) = @_;
    my ($details);
    $details = $page->locator(('#' . $element_id));
    if (truth_value((!defined($details->getAttribute('open'))))) {
        $details->locator(':scope > summary')->click();
    }
}
sub share_room {
    my ($page) = @_;
    $page->locator('#copyInviteBtn')->click();
    wait_js($page, '() => leqra.getState().phase === \'onlineLobby\'');
    return evaluate_js($page, 'leqra.getState().online.code');
}
sub check_promotion {
    my ($browser, $url, $errors) = @_;
    my ($code, $guest, $guest_context, $host, $host_context, $original, $page, $persisted, $size);
    $host_context = $browser->newContext();
    $guest_context = $browser->newContext();
    $host = main::load_room($host_context, $url, $errors);
    $guest = main::load_room($guest_context, $url, $errors);
    for my $item (@{[[$host, 'large'], [$guest, 'compact']]}) {
        my $tuple_40_12 = $item;
        my $page = $tuple_40_12->[0];
        my $size = $tuple_40_12->[1];
        main::open_details($page, 'roomSettings');
        $page->locator('#roomMapSize')->selectOption($size);
    }
    $persisted = 'localStorage.getItem(\'leqra.roomSetup.v2\')';
    $original = evaluate_js($guest, $persisted);
    assert_ok((value_eq(decode_json($original)->{'modes'}->{'elimination'}->{'mapSize'}, 'compact')), 'json.loads(original)["modes"]["elimination"]["mapSize"] == "compact"');
    $code = main::share_room($host);
    $guest->locator('#joinOtherBtn')->click();
    $guest->locator('#joinCode')->fill($code);
    $guest->locator('#pilotName')->fill('GUEST');
    $guest->locator('#joinRoomBtn')->click();
    wait_js($guest, '() => leqra.getState().phase === \'onlineLobby\'');
    expect_locator($guest->locator('#roomMapSize'), 'to_have_value', 'large');
    assert_ok((value_eq(evaluate_js($guest, $persisted), $original)), 'guest.evaluate(persisted) == original');
    $host->close();
    wait_js($guest, '() => {
            const state = leqra.getState();
            return state.room.host === state.online.id;
        }');
    expect_locator($guest->locator('#roomMapSize'), 'to_have_value', 'large');
    assert_ok((value_eq(evaluate_js($guest, $persisted), $original)), 'guest.evaluate(persisted) == original');
    $guest->locator('#leaveRoomBtn')->click();
    wait_js($guest, '() => leqra.getState().mode === \'room\'');
    expect_locator($guest->locator('#roomMapSize'), 'to_have_value', 'compact');
    $guest_context->close();
    $host_context->close();
    print(join(" ", 'PASS host promotion keeps the guest\'s local setup'), "\n");
}
sub check_roster_focus {
    my ($browser, $url, $errors) = @_;
    my ($context, $control, $details, $online, $original, $page, $roster, $select, $team, $value);
    for $online (@{[JSON::PP::false, JSON::PP::true]}) {
        $context = $browser->newContext();
        $page = main::load_room($context, $url, $errors);
        $page->locator('#infinityToggle')->uncheck();
        if (truth_value($online)) {
            main::share_room($page);
        }
        for $details (@{['roomSettings', 'roomPlayers']}) {
            main::open_details($page, $details);
        }
        $page->locator('#addBotBtn')->click();
        $roster = $page->locator('#roomRoster .seat-row');
        expect_locator($roster, 'to_have_count', 5);
        for my $item (@{[['select[data-bot-difficulty="1"]', 'hard'], ['select[data-tank-color="1"]', '2']]}) {
            my $tuple_81_16 = $item;
            my $control = $tuple_81_16->[0];
            my $value = $tuple_81_16->[1];
            my $select = $page->locator(('#roomRoster ' . $control));
            my $original = $select->elementHandle();
            $select->focus();
            $select->selectOption($value);
            wait_js($page, 'node => !node.isConnected', $original, {});
            expect_locator($select, 'to_have_value', $value);
            expect_locator($select, 'to_be_focused');
        }
        $page->locator('#roomTeamMode')->selectOption('teams');
        $team = $page->locator('#roomRoster select[data-team="1"]');
        expect_locator($team, 'to_have_value', '1');
        $team->focus();
        $team->selectOption('2');
        expect_locator($team, 'to_have_value', '2');
        expect_locator($team, 'to_be_focused');
        assert_ok((value_eq(inspect_elements($page, '#roomRoster .seat-row', 'rows => rows.map(row => row.dataset.seat)'), ['0', '2', '1', '3', '4'])), 'roster.evaluate_all("rows => rows.map(row => row.dataset.seat)") == ["0", "2", "1", "3", "4"]');
        $context->close();
    }
    print(join(" ", 'PASS local and online roster changes preserve keyboard focus'), "\n");
}
sub check_chat_composition {
    my ($browser, $url, $errors) = @_;
    my ($cdp, $chat, $context, $page);
    $context = $browser->newContext();
    $page = main::load_room($context, $url, $errors);
    main::share_room($page);
    $page->locator('#chatBtn')->click();
    $chat = $page->locator('#chatInput');
    expect_locator($chat, 'to_be_focused');
    evaluate_js($page, '() => {
            window.testEscapeComposition = [];
            window.addEventListener(\'keydown\', event => {
                if (event.code === \'Escape\') testEscapeComposition.push(event.isComposing);
            }, true);
        }');
    $cdp = $context->newCDPSession($page);
    $cdp->send('Input.imeSetComposition', {'text' => '田中', 'selectionStart' => 2, 'selectionEnd' => 2});
    $page->keyboard()->press('Escape');
    assert_ok((value_eq(evaluate_js($page, 'window.testEscapeComposition'), [JSON::PP::true])), 'page.evaluate("window.testEscapeComposition") == [True]');
    expect_locator($page->locator('#chatPanel'), 'to_be_visible');
    expect_locator($chat, 'to_be_focused');
    $cdp->send('Input.imeSetComposition', {'text' => '', 'selectionStart' => 0, 'selectionEnd' => 0});
    $page->keyboard()->press('Escape');
    expect_locator($page->locator('#chatPanel'), 'to_be_hidden');
    $context->close();
    print(join(" ", 'PASS composing Escape stays in chat and ordinary Escape closes it'), "\n");
}
sub frame_type {
    my ($payload, $expected) = @_;
    eval {
        return (value_eq((decode_json($payload)->{'type'} // undef), $expected));
    1;
    };
    if ($@) {
        return JSON::PP::false;
    }
}
sub check_queue_notice {
    my ($browser, $url, $errors) = @_;
    my ($unused, $connection, $context, $message, $notice, $page, $socket);
    $context = $browser->newContext();
    $page = main::load_room($context, $url, $errors);
    $page->locator('#matchmakingBtn')->click();
    my $pending_140 = $page->waitForEvent('websocket');
    $connection = {};
    $page->locator('#queueStartBtn')->click();
    my $event_140 = $Leqra::Browser::HANDLE->await($pending_140);
    $connection->{'value'} = $event_140;
    $socket = $connection->{'value'};
    expect_locator($page->locator('#queueActive'), 'to_be_visible');
    my $events_144 = [];
    capture_event($socket, 'framereceived', $events_144, "value => value");
    $page->locator('#queueCancelBtn')->click();
    wait_event_log($events_144, sub { my ($payload) = @_; return main::frame_type($payload, 'room'); }, 30000);
    $notice = $page->locator('#queueNotice');
    $message = 'Matchmaking cancelled. Your party is still together in this room.';
    expect_locator($notice, 'to_be_visible');
    expect_locator($notice, 'to_have_text', $message);
    expect_locator($page->locator('#queueActive'), 'to_be_hidden');
    for my $unused (@{[0 .. 2 - 1]}) {
        $page->locator('#queueCloseBtn')->click();
        my $events_155 = [];
        capture_event($socket, 'framereceived', $events_155, "value => value");
        $page->locator('#matchmakingBtn')->click();
        wait_event_log($events_155, sub { my ($payload) = @_; return main::frame_type($payload, 'queue_catalog'); }, 30000);
        expect_locator($notice, 'to_have_text', $message);
    }
    $page->locator('[data-queue="elimination-2"]')->click();
    expect_locator($notice, 'not_to_have_text', $message);
    $context->close();
    print(join(" ", 'PASS queue cancellation stays visible through room and catalog updates'), "\n");
}
unless (caller) {
    $parser = {};
    $url = (trim_text(do { my %args = ('url' => ((\%ENV)->{'LEQRA_URL'} // 'http://localhost:8080')); my $help; GetOptions('help|h' => \$help) or die 'Usage: perl audit_browser.pl url
'; if ($help) { print 'Usage: perl audit_browser.pl url
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; }->{'url'}, '/', 'rstrip') . '/');
    $errors = [];
    $playwright = start_playwright();
    $browser = $playwright->launch(type => 'chrome', chromiumSandbox => JSON::PP::true);
    eval {
        main::check_promotion($browser, $url, $errors);
        main::check_roster_focus($browser, $url, $errors);
        main::check_chat_composition($browser, $url, $errors);
        main::check_queue_notice($browser, $url, $errors);
    1;
    };
    my $caught_error = $@;
    $browser->close();
    die $caught_error if $caught_error;
    assert_ok((!truth_value($errors)), $errors);
}
