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

my ( $args, $browser, $errors, $parser, $playwright, $url );

# Exercise Infinity in Chromium against a dedicated leqra server.
#
# Start the current server with `go run ./src`, then run
# `perl src/tests/infinity_browser.pl [http://localhost:8080]`.
# LEQRA_URL can supply the URL. Install Playwright and Chromium first.
sub load {
    my ( $context, $url, $name, $errors ) = @_;
    my ($page);
    $page = $context->newPage();
    capture_event( $page, 'pageerror', $errors, '(error) => String(error)' );
    $page->addInitScript(
        ( '
        try {
            localStorage.setItem(\'leqra.name\', ' . json_text($name) . ');
            localStorage.setItem(\'leqra.introTour.v1\', \'1\');
        } catch {}
    ' )
    );
    $page->goto($url);
    wait_js( $page, '() => !!window.leqraInfinity' );
    return $page;
}

sub select_room_infinity {
    my ($page) = @_;
    my ( $mode, $settings );
    $settings = $page->locator('#roomSettings');
    $settings->locator('summary')->click();
    $mode = $settings->locator('[data-room-mode="infinity"]');
    $mode->click();
    expect_locator( $mode, 'to_have_attribute', 'aria-checked', 'true' );
}

sub expect_pilots {
    my ( $page, $count ) = @_;
    expect_locator( $page->locator('#infiniteArena'), 'to_be_visible' );
    expect_locator( $page->locator('#infiniteOnlineCount'),
        'to_contain_text', regex( ( '\\b' . $count . ' online\\b' ) ) );
}

sub expect_score_rank {
    my ( $page, $split ) = @_;
    my ( $counter, $counters, $index );
    $split //= JSON::PP::false;
    $counters = $page->locator('#infiniteKills .infinite-personal-score');
    expect_locator( $counters, 'to_have_count', ( truth_value($split) ? 2 : 1 ) );
    for $index ( @{ [ 0 .. ( truth_value($split) ? 2 : 1 ) - 1 ] } ) {
        $counter = $counters->nth($index);
        expect_locator( $counter->locator('.infinite-score-name'),
            'to_contain_text', regex( ( '\\(P' . ( $index + 1 ) . '\\)$' ) ) );
        expect_locator( $counter->locator('.infinite-score-value'),
            'to_have_text', regex('^score: -?\\d+, rank: #[1-9]\\d*$') );
    }
}

sub standings {
    my ($page) = @_;
    my ($panel);
    $panel = $page->locator('#infiniteLeaderboardPanel');
    if ( truth_value( ( !defined( $panel->getAttribute('open') ) ) ) ) {
        $page->locator('#infiniteScoreboardBtn')->press('Space');
    }
    expect_locator( $panel, 'to_have_attribute', 'open', '' );
    return $panel->locator('#infiniteLeaderboard');
}

sub is_packet {
    my ( $frame, $kind, $fields ) = @_;
    my ( $key, $packet, $value );
    $fields //= {};
    if ( truth_value( ( !truth_value( ( !ref($frame) ) ) ) ) ) {
        return JSON::PP::false;
    }
    $packet = decode_json($frame);
    return (
        do {
            my $boolean_value =
              ( value_eq( ( $packet->{'type'} // undef ), $kind ) );
            truth_value($boolean_value)
              ? !scalar(
                grep {
                    my ( $key, $value ) = @{$_};
                    !( ( value_eq( ( $packet->{$key} // JSON::PP::false ), $value ) ) )
                } @{ [ map { [ $_, $fields->{$_} ] } keys %{$fields} ] }
              )
              : $boolean_value;
        }
    );
}

sub check_pause_style {
    my ( $page, $online ) = @_;
    my (
        $actual,          $actual_style, $back,  $card,       $fixed,
        $heading,         $message,      $pause, $properties, $reference,
        $reference_style, $sidebar,      $style
    );
    $pause = $page->locator('#infinitePauseMenu');
    assert_ok(
        evaluate_js( $pause, 'dialog => dialog.matches(\':modal\')' ),
        'pause.evaluate("dialog => dialog.matches(\':modal\')")'
    );
    $card    = $pause->locator('.screen-card');
    $fixed   = $page->locator( ( truth_value($online) ? '#onlineMenuScreen' : '#pauseScreen' ) );
    $heading = $card->getByRole(
        'heading',
        {
            name  => ( truth_value($online) ? 'STAY CONNECTED.' : 'HOLD YOUR FIRE.' ),
            exact => JSON::PP::true
        }
    );
    $back = $card->getByRole(
        'button',
        {
            name => (
                truth_value($online)
                ? 'BACK TO THE ARENA'
                : 'BACK TO THE BATTLE'
            ),
            exact => JSON::PP::true
        }
    );
    expect_locator( $heading, 'to_be_visible' );
    expect_locator( $back,    'to_be_focused' );
    $message = $card->locator('p')->filter(
        {
            hasText => ( truth_value($online) ? 'respawning waits' : 'Your tank is safe' )
        }
    );
    expect_locator( $message, 'to_be_visible' );
    $sidebar = $pause->locator('#infinitePauseSidebar #gameSidebar');
    expect_locator( $sidebar,                                       'to_be_visible' );
    expect_locator( $sidebar->locator('#infiniteLeaderboardPanel'), 'to_have_attribute', 'open', '' );
    expect_locator( $sidebar->locator('#manualContent .warning'),   'to_contain_text',   'INFINITY' );
    expect_locator( $sidebar->locator('.power-row'),                'to_have_count',     10 );
    expect_locator( $sidebar->locator('.power-note'), 'to_contain_text', 'Starman lasts 8 seconds' );
    expect_locator( $sidebar->locator('.power-row')->filter( { hasText => 'Cannon' } ),
        'to_contain_text', '5.3s flight' );
    expect_locator( $sidebar->locator('.fixed-maze-panel'), 'to_be_hidden' );
    expect_locator( $sidebar->locator('.log-panel'),        'to_be_hidden' );
    $style = sub {
        my ( $locator, $properties ) = @_;
        return evaluate_js(
            $locator, '(node, properties) => {
            const computed = getComputedStyle(node);
            return properties.map(name => computed.getPropertyValue(name));
        }', $properties
        );
    };
    for my $item (
        @{
            [
                [ $card,    $fixed, [ 'background-image', 'border-radius', 'box-shadow' ] ],
                [ $heading, $fixed->locator('.compact-title'), [ 'font-weight', 'font-family' ] ],
                [
                    $back, $fixed->locator('.back-action'),
                    [ 'background-color', 'border-radius', 'font-weight' ]
                ]
            ]
        }
      )
    {
        my $tuple_96_8      = $item;
        my $actual          = $tuple_96_8->[0];
        my $reference       = $tuple_96_8->[1];
        my $properties      = $tuple_96_8->[2];
        my $tuple_101_8     = [ $style->( $actual, $properties ), $style->( $reference, $properties ) ];
        my $actual_style    = $tuple_101_8->[0];
        my $reference_style = $tuple_101_8->[1];
        assert_ok(
            ( value_eq( $actual_style, $reference_style ) ),
            [ $properties, $actual_style, $reference_style ]
        );
    }
}

sub check_online_pause {
    my ( $page, $socket ) = @_;
    my ( $arena, $canvas, $controls, $forward, $neutral, $pause, $pickup_info, $resume );
    $arena  = $page->locator('#infiniteArena');
    $pause  = $page->locator('#infinitePauseMenu');
    $resume = $pause->locator('#infiniteResumeBtn');
    $canvas = $page->locator('#infiniteCanvas');
    $canvas->focus();
    my $events_111 = [];
    capture_event( $socket, 'framesent', $events_111, "value => value" );
    $page->keyboard()->down('w');
    wait_event_log(
        $events_111,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input', { 'forward' => JSON::PP::true } );
        },
        30000
    );
    $neutral = {
        'forward' => JSON::PP::false,
        'reverse' => JSON::PP::false,
        'left'    => JSON::PP::false,
        'right'   => JSON::PP::false,
        'fire'    => JSON::PP::false,
        'stickX'  => 0,
        'stickY'  => 0
    };
    my $events_114 = [];
    capture_event( $socket, 'framesent', $events_114, "value => value" );
    $page->keyboard()->press('Escape');
    wait_event_log(
        $events_114,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input', { 'paused' => JSON::PP::true } );
        },
        30000
    );
    my $events_116 = [];
    capture_event( $socket, 'framereceived', $events_116, "value => value" );
    $page->keyboard()->up('w');
    wait_event_log( $events_116, sub { my ($frame) = @_; return main::is_packet( $frame, 'state' ); },
        30000 );
    expect_locator( $arena, 'to_be_visible' );
    expect_locator( $pause, 'to_be_visible' );
    main::check_pause_style( $page, JSON::PP::true );
    $pause->locator('#infiniteControlsBtn')->click();
    $controls = $page->locator('#controlsDialog');
    expect_locator( $controls, 'to_be_visible' );
    expect_locator( $controls->locator('#controlsPickupInfo'), 'to_have_count', 0 );
    $pickup_info = $page->locator('#gameSidebar .power-note');
    expect_locator( $pickup_info, 'to_contain_text', 'Most last 15 seconds' );
    expect_locator( $pickup_info, 'to_contain_text', 'Starman lasts 8 seconds' );
    expect_locator( $pickup_info, 'to_contain_text', 'expire after 30 seconds' );
    $controls->locator('#showFPS')->check();
    expect_locator( $page->locator('#infiniteFPSIndicator'), 'to_have_text', regex('\\d+ FPS, [\\d.]+ ms') );
    $controls->locator('#showFPS')->uncheck();
    expect_locator( $page->locator('#infiniteFPSIndicator'), 'to_be_hidden' );
    $forward = $controls->locator('[data-bind="0:forward"]');
    $forward->click();
    $page->keyboard()->press('e');
    expect_locator( $forward, 'to_have_text', 'E' );
    $page->keyboard()->press('Escape');
    expect_locator( $controls, 'to_be_hidden' );
    expect_locator( $pause,    'to_be_visible' );
    my $events_142 = [];
    capture_event( $socket, 'framesent', $events_142, "value => value" );
    $resume->click();
    wait_event_log(
        $events_142,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input', { 'paused' => JSON::PP::false } );
        },
        30000
    );
    expect_locator( $pause,  'to_be_hidden' );
    expect_locator( $canvas, 'to_be_focused' );
    my $events_146 = [];
    capture_event( $socket, 'framesent', $events_146, "value => value" );
    $page->keyboard()->down('e');
    wait_event_log(
        $events_146,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input',
                { 'paused' => JSON::PP::false, 'forward' => JSON::PP::true } );
        },
        30000
    );
    $page->keyboard()->up('e');
    $page->keyboard()->press('Escape');
    expect_locator( $pause, 'to_be_visible' );
    my $events_151 = [];
    capture_event( $socket, 'framesent', $events_151, "value => value" );
    $page->keyboard()->press('Escape');
    wait_event_log(
        $events_151,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input', { 'paused' => JSON::PP::false } );
        },
        30000
    );
    expect_locator( $pause,  'to_be_hidden' );
    expect_locator( $canvas, 'to_be_focused' );
    my $events_155 = [];
    capture_event( $socket, 'framesent', $events_155, "value => value" );
    $page->keyboard()->press('p');
    wait_event_log(
        $events_155,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input', { 'paused' => JSON::PP::true } );
        },
        30000
    );
    expect_locator( $pause, 'to_be_visible' );
}

sub check_touch_controls {
    my ( $context, $page ) = @_;
    my ( $cdp, $expect_released, $fire, $knob, $portrait, $press_both, $stick );
    $stick = $page->locator('#infiniteStick');
    $knob  = $page->locator('#infiniteKnob');
    $fire  = $page->locator('#infiniteFire');
    expect_locator( $page->locator('html'), 'to_have_class', regex('\\bmatch-active\\b') );
    assert_ok(
        evaluate_js(
            $page, '() => {
        const pinch = new Event(\'gesturechange\', {bubbles:true, cancelable:true});
        document.dispatchEvent(pinch);
        return pinch.defaultPrevented;
    }'
        ),
        'page.evaluate("""() => {
        const pinch = new Event(\'gesturechange\', {bubbles:true, cancelable:true});
        document.dispatchEvent(pinch);
        return pinch.defaultPrevented;
    }""")'
    );
    evaluate_js(
        $page, '() => {
        Element.prototype.setPointerCapture = () => { throw new DOMException(\'Pointer expired\', \'NotFoundError\'); };
    }'
    );
    expect_locator( $stick, 'to_be_visible' );
    expect_locator( $fire,  'to_be_visible' );
    $cdp        = $context->newCDPSession($page);
    $press_both = sub {
        my ( $fire_box, $points, $stick_box );
        my $tuple_178_8 = [ $stick->boundingBox(), $fire->boundingBox() ];
        $stick_box = $tuple_178_8->[0];
        $fire_box  = $tuple_178_8->[1];
        $points    = [
            {
                'x'  => ( $stick_box->{'x'} + ( 0.7 * $stick_box->{'width'} ) ),
                'y'  => ( $stick_box->{'y'} + ( 0.5 * $stick_box->{'height'} ) ),
                'id' => 11
            },
            {
                'x'  => ( $fire_box->{'x'} + ( 0.5 * $fire_box->{'width'} ) ),
                'y'  => ( $fire_box->{'y'} + ( 0.5 * $fire_box->{'height'} ) ),
                'id' => 12
            }
        ];
        $cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => $points } );
        expect_locator( $fire, 'to_have_class', regex('\\bheld\\b') );
        assert_ok(
            (
                !(
                    contains_value(
                        [ '', '0px' ],
                        evaluate_js( $knob, 'element => element.style.getPropertyValue(\'--stick-x\')' )
                    )
                )
            ),
            'knob.evaluate("element => element.style.getPropertyValue(\'--stick-x\')") not in ("", "0px")'
        );
    };
    $expect_released = sub {
        expect_locator( $fire, 'not_to_have_class', regex('\\bheld\\b') );
        assert_ok(
            (
                value_eq(
                    evaluate_js( $knob, 'element => element.style.getPropertyValue(\'--stick-x\')' ), ''
                )
            ),
            'knob.evaluate("element => element.style.getPropertyValue(\'--stick-x\')") == ""'
        );
    };
    $portrait = $page->viewportSize();
    $press_both->();
    $page->setViewportSize( { 'width' => $portrait->{'height'}, 'height' => $portrait->{'width'} } );
    wait_js( $page, '() => leqra.getState().touchLandscape' );
    $expect_released->();
    $cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchCancel', 'touchPoints' => [] } );
    $press_both->();
    $cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchCancel', 'touchPoints' => [] } );
    $expect_released->();
    $page->setViewportSize($portrait);
    wait_js( $page, '() => !leqra.getState().touchLandscape' );
}

sub check_public {
    my ( $browser, $url, $errors ) = @_;
    my ( $connection, $first, $guest, $host, $leaders, $page, $second );
    $first  = $browser->newContext();
    $second = $browser->newContext();
    $host   = main::load( $first,  $url, 'PUBLIC HOST',  $errors );
    $guest  = main::load( $second, $url, 'PUBLIC GUEST', $errors );
    for $page ( @{ [ $host, $guest ] } ) {
        expect_locator( $page->locator('#infinityToggle'), 'to_be_checked' );
        expect_locator(
            $page->locator('button:text-matches("^play$","i"), [role="button"]:text-matches("^play$","i")'),
            'to_have_count', 1 );
    }
    my $pending_211 = $host->waitForEvent('websocket');
    $connection = {};
    $host->locator('#startRoomBtn')->click();
    my $event_211 = $Leqra::Browser::HANDLE->await($pending_211);
    $connection->{'value'} = $event_211;
    assert_ok(
        (
            sub {
                my ($ws) = @_;
                return ( substr( $ws->url(), -length('/ws/infinite') ) eq '/ws/infinite' );
            }
        )->($event_211),
        "Unexpected WebSocket event"
    );
    main::expect_pilots( $host, 1 );
    expect_locator( $host->locator('#infiniteLeaderboardTitle'), 'to_have_text', 'LEADERBOARD' );
    $guest->locator('#startRoomBtn')->click();

    for $page ( @{ [ $host, $guest ] } ) {
        main::expect_pilots( $page, 2 );
        main::expect_score_rank($page);
        expect_locator( $page->locator('#infiniteLeaderboardTitle'), 'to_have_text', 'LEADERBOARD' );
        $leaders = main::standings($page);
        expect_locator( $leaders, 'to_contain_text', 'PUBLIC HOST' );
        expect_locator( $leaders, 'to_contain_text', 'PUBLIC GUEST' );
        assert_ok( ( ( $leaders->locator('li')->count() <= 10 ) ), 'leaders.locator("li").count() <= 10' );
    }
    main::check_online_pause( $host, $connection->{'value'} );
    main::expect_pilots( $guest, 2 );
    $host->locator('#infiniteExit')->click();
    expect_locator( $host->locator('#infiniteArena'), 'to_be_hidden' );
    expect_locator( $host->locator('#startRoomBtn'),  'to_be_focused' );
    main::expect_pilots( $guest, 1 );
    expect_locator( $guest->locator('#infiniteLeaderboardTitle'), 'to_have_text', 'LEADERBOARD' );
    $host->locator('#infinityToggleLabel')->click();
    expect_locator( $host->locator('#infinityToggle'), 'not_to_be_checked' );
    $host->locator('#startRoomBtn')->click();
    wait_js( $host, '() => [\'countdown\',\'playing\'].includes(leqra.getState().phase)' );
    expect_locator( $host->locator('#infiniteArena'), 'to_be_hidden' );
    $host->keyboard()->press('Escape');
    expect_locator( $host->locator('#onlineMenuScreen'), 'to_be_visible' );
    assert_ok( ( value_eq( evaluate_js( $host, 'leqra.getState().phase' ), 'paused' ) ),
        'host.evaluate("leqra.getState().phase") == "paused"' );
    $host->keyboard()->press('Escape');
    expect_locator( $host->locator('#onlineMenuScreen'), 'to_be_hidden' );
    $second->close();
    $first->close();
    print( join( " ", 'PASS public Infinity pause, control rebinding, remote standings, and classic Escape' ),
        "\n" );
}

sub check_offline {
    my ( $browser, $errors ) = @_;
    my ( $context, $index, $page, $panel );
    $index   = path($0)->absolute->parent(2)->child('web')->child('index.html');
    $context = $browser->newContext(
        {
            viewport => { 'width' => 320, 'height' => 568 },
            isMobile => JSON::PP::true,
            hasTouch => JSON::PP::true
        }
    );
    $page = main::load( $context, URI::file->new_abs( "" . $index )->as_string, 'OFFLINE PILOT', $errors );
    expect_locator( $page->locator('#infinityToggle'), 'to_be_disabled' );
    main::select_room_infinity($page);
    $page->locator('#startRoomBtn')->tap();
    expect_locator( $page->locator('#infiniteArena'),       'to_be_visible' );
    expect_locator( $page->locator('#infiniteStatus'),      'to_be_hidden' );
    expect_locator( $page->locator('#infiniteOnlineCount'), 'to_be_hidden' );
    main::expect_score_rank($page);
    $panel = $page->locator('#infiniteLeaderboardPanel');
    $page->locator('#infiniteScoreboardBtn')->tap();
    expect_locator( $panel->locator('#infiniteLeaderboard'), 'to_contain_text', 'OFFLINE PILOT (P1)' );
    expect_locator( $panel->locator('#infiniteLeaderboard'), 'to_contain_text', 'RUST' );
    main::check_touch_controls( $context, $page );
    $page->locator('#pauseBtn')->tap();
    main::check_pause_style( $page, JSON::PP::false );
    $page->locator('#infiniteExit')->tap();
    expect_locator( $page->locator('#infiniteArena'), 'to_be_hidden' );
    expect_locator( $page->locator('html'), 'not_to_have_class', regex('\\bmatch-active\\b') );
    expect_locator( $page->locator('[data-room-mode="infinity"]'),
        'to_have_attribute', 'aria-checked', 'true' );
    $context->close();
    print( join( " ", 'PASS offline file launch, mobile controls, roster bots, and standings' ), "\n" );
}

sub check_audio {
    my ( $browser, $errors ) = @_;
    my ( $context, $index, $initial, $muted, $page, $sound );
    $index   = path($0)->absolute->parent(2)->child('web')->child('index.html');
    $context = $browser->newContext();
    $context->addInitScript( '
            window.oscillatorStarts = 0;
            const start = OscillatorNode.prototype.start;
            OscillatorNode.prototype.start = function (...args) {
                window.oscillatorStarts++;
                return start.apply(this, args);
            };
        ' );
    $page = main::load( $context, URI::file->new_abs( "" . $index )->as_string, 'SOUND PILOT', $errors );
    main::select_room_infinity($page);
    $page->locator('#startRoomBtn')->click();
    expect_locator( $page->locator('#infiniteStatus'), 'to_be_hidden' );
    $initial = evaluate_js( $page, 'oscillatorStarts' );
    $page->keyboard()->press('q');
    wait_js( $page, '(initial) => oscillatorStarts > initial', $initial, {} );
    $sound = $page->locator('#soundBtn');
    $sound->click();
    expect_locator( $sound, 'to_have_attribute', 'aria-label', 'Unmute sound' );
    $muted = evaluate_js( $page, 'oscillatorStarts' );
    $page->locator('#infiniteCanvas')->focus();
    $page->keyboard()->down('q');
    $Leqra::Browser::HANDLE->await( $page->waitForTimeout(400) );
    $page->keyboard()->up('q');
    assert_ok( ( value_eq( evaluate_js( $page, 'oscillatorStarts' ), $muted ) ),
        'page.evaluate("oscillatorStarts") == muted' );
    $page->locator('#pauseBtn')->click();
    $page->locator('#infiniteExit')->click();
    expect_locator( $page->locator('#soundBtn'), 'to_have_attribute', 'aria-label', 'Unmute sound' );
    $context->close();
    print( join( " ", 'PASS Infinity uses the shared firing audio and mute setting' ), "\n" );
}

sub check_pause_sidebar {
    my ( $browser, $url, $errors ) = @_;
    my (
        $arena_center, $card_center, $context, $expected_width, $gap,
        $height,       $layout,      $note,    $page,           $player_count,
        $sidebar,      $touch,       $width
    );
    for my $item (
        @{
            [
                [ 1560, 900, JSON::PP::false ],
                [ 1280, 900, JSON::PP::false ],
                [ 1000, 800, JSON::PP::false ],
                [ 390,  844, JSON::PP::true ],
                [ 320,  568, JSON::PP::true ],
                [ 568,  320, JSON::PP::true ]
            ]
        }
      )
    {
        my $tuple_304_8 = $item;
        my $width       = $tuple_304_8->[0];
        my $height      = $tuple_304_8->[1];
        my $touch       = $tuple_304_8->[2];
        my $context     = $browser->newContext(
            {
                viewport => { 'width' => $width, 'height' => $height },
                isMobile => $touch,
                hasTouch => $touch
            }
        );
        $context->addInitScript('localStorage.setItem(\'leqra.sidebarHidden\',\'1\')');
        my $page = main::load( $context, $url, 'SIDEBAR PILOT', $errors );
        main::select_room_infinity($page);
        $page->locator('#roomPlayers > summary')->click();
        $page->locator('#addLocalBtn')->click();
        my $player_count = evaluate_js( $page, 'leqra.getState().room.players.length' );
        $page->locator('#startRoomBtn')->click();
        expect_locator( $page->locator('#infiniteArena'), 'to_be_visible' );
        evaluate_js(
            $page, '() => {
                const sidebar = document.querySelector(\'#gameSidebar\');
                document.querySelector(\'#sidebarDetails\').append(sidebar);
                const dialog = document.querySelector(\'#sidebarDialog\');
                dialog.showModal(); dialog.close();
                document.querySelector(\'#pauseBtn\').click();
            }'
        );
        my $sidebar = $page->locator('#infinitePauseSidebar #gameSidebar');
        expect_locator( $sidebar,                                       'to_be_visible' );
        expect_locator( $sidebar->locator('#infiniteLeaderboardPanel'), 'to_have_attribute', 'open', '' );
        expect_locator( $sidebar->locator('#infiniteLeaderboard li'),   'to_have_count',     $player_count );
        expect_locator( $page->locator('#infiniteLeaderboardPanel'),    'to_have_count',     1 );
        expect_locator( $sidebar->locator('#manualContent .control-pilot')->last(),
            'to_contain_text', '(P2)' );
        expect_locator( $sidebar->locator('#manualContent .warning'), 'to_contain_text', 'INFINITY' );
        expect_locator( $sidebar->locator('.power-row'),              'to_have_count',   10 );
        my $layout = evaluate_js(
            $page->locator('#infinitePauseMenu'), 'menu => {
                const box = node => {const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width};};
                return {sidebar:box(menu.querySelector(\'#infinitePauseSidebar\')),card:box(menu.querySelector(\'.screen-card\')),layout:box(menu.querySelector(\'.infinite-pause-layout\'))};
            }'
        );

        if ( truth_value( ( !truth_value($touch) ) ) ) {
            my $expected_width =
              ( truth_value( ( ( $width <= 1150 ) ) ) ? 239 : 266 );
            assert_ok( ( ( abs( ( $layout->{'sidebar'}->{'right'} - ( $width - 14 ) ) ) <= 1 ) ), $layout );
            assert_ok( ( ( abs( ( $layout->{'sidebar'}->{'width'} - $expected_width ) ) <= 1 ) ), $layout );
            my $gap         = ( truth_value( ( ( $width <= 1150 ) ) ) ? 15 : 20 );
            my $card_center = ( ( $layout->{'card'}->{'left'} + $layout->{'card'}->{'right'} ) / 2 );
            my $arena_center =
              ( ( ( $layout->{'layout'}->{'left'} + $layout->{'sidebar'}->{'left'} ) - $gap ) / 2 );
            assert_ok( ( ( abs( ( $card_center - $arena_center ) ) <= 1 ) ), $layout );
        }
        else {
            assert_ok( ( ( $layout->{'sidebar'}->{'top'} >= $layout->{'card'}->{'bottom'} ) ), $layout );
        }
        my $note = $sidebar->locator('.power-note');
        $note->scrollIntoViewIfNeeded();
        expect_locator( $note, 'to_be_in_viewport' );
        expect_locator( $note, 'to_contain_text', 'Starman lasts 8 seconds' );
        assert_ok(
            evaluate_js(
                $page->locator('#infinitePauseMenu'),
                'node => node.scrollWidth <= node.clientWidth + 1'
            ),
            'page.locator("#infinitePauseMenu").evaluate("node => node.scrollWidth <= node.clientWidth + 1")'
        );
        $page->locator('#infiniteControlsBtn')->click();
        $page->locator('[data-bind="1:fire"]')->click();
        $page->keyboard()->press('u');
        $page->locator('#openIntroTour')->click();
        expect_locator( $page->locator('#introTourDialog'), 'to_be_visible' );
        $page->locator('#introTourSkip')->click();
        $page->keyboard()->press('Escape');
        expect_locator( $page->locator('#controlsDialog'),            'to_be_hidden' );
        expect_locator( $page->locator('#infiniteControlsBtn'),       'to_be_focused' );
        expect_locator( $sidebar->locator('#manualContent'),          'to_contain_text', 'U / ENTER' );
        expect_locator( $sidebar->locator('#manualContent .warning'), 'to_contain_text', 'INFINITY' );
        $page->locator('#infiniteResumeBtn')->click();
        expect_locator( $page->locator('.main-grid > #gameSidebar'),                   'to_have_count', 1 );
        expect_locator( $page->locator('.infinite-stage > #infiniteLeaderboardPanel'), 'to_have_count', 1 );
        assert_ok(
            (
                !truth_value(
                    evaluate_js( $page->locator('#infiniteLeaderboardPanel'), 'node => node.open' )
                )
            ),
            'not page.locator("#infiniteLeaderboardPanel").evaluate("node => node.open")'
        );
        expect_locator( $page->locator('#infiniteCanvas'), 'to_be_focused' );
        $page->locator('#pauseBtn')->click();
        $page->locator('#infiniteExit')->click();
        expect_locator( $page->locator('.main-grid > #gameSidebar'),                   'to_have_count', 1 );
        expect_locator( $page->locator('.infinite-stage > #infiniteLeaderboardPanel'), 'to_have_count', 1 );
        expect_locator( $page->locator('#gameSidebar .power-note'),
            'to_contain_text', 'Most timed power-ups last 10 seconds' );

        if ( truth_value($touch) ) {
            $page->locator('#sidebarDetailsBtn')->click();
            expect_locator( $page->locator('#sidebarDetails > #gameSidebar'), 'to_be_visible' );
            $page->locator('#sidebarCloseBtn')->click();
            expect_locator( $page->locator('.main-grid > #gameSidebar'), 'to_have_count', 1 );
        }
        $context->close();
    }
    print(
        join( " ",
            'PASS shared Infinity pause sidebar, nested tour, bindings, scrolling, and DOM restoration' ),
        "\n"
    );
}

sub check_private {
    my ( $browser, $url, $errors ) = @_;
    my (
        $before,          $close_with_escape, $context,      $drop,          $first,
        $frame,           $guest,             $guest_frames, $guest_welcome, $host,
        $host_frames,     $key,               $leaders,      $moderator,     $other,
        $outsider,        $page,              $paths,        $pilot,         $public,
        $record_infinity, $rejoined,          $resumed,      $room_code,     $second,
        $socket,          $welcome
    );
    $first  = $browser->newContext();
    $second = $browser->newContext();
    $public = $browser->newContext();
    $first->addInitScript('localStorage.setItem(\'leqra.local2Name\', \'ROOM WING\')');
    for $context ( @{ [ $first, $second ] } ) {
        $context->addInitScript( '
                window.gameSockets = [];
                window.WebSocket = class extends WebSocket {
                    constructor(...args) {
                        super(...args);
                        gameSockets.push(this);
                    }
                };
            ' );
    }
    $host = main::load( $first, $url, 'ROOM HOST', $errors );
    main::select_room_infinity($host);
    $host->locator('#roomTeamMode')->selectOption('teams');
    $host->locator('#roomRulesBtn')->click();
    $host->locator('#rule-infinityTarget')->fill('999');
    $host->locator('#rule-teamName1')->fill('Orcas');
    $host->locator('#applyRulesBtn')->click();
    expect_locator( $host->locator('#rulesDialog'), 'to_be_hidden' );
    $host->locator('#roomPlayers > summary')->click();
    $host->locator('#addLocalBtn')->click();
    expect_locator( $host->locator('#roomRoster'), 'to_contain_text', 'ROOM WING' );
    $host->locator('#copyInviteBtn')->click();
    wait_js( $host, '() => !!leqra.getState().online?.connected' );
    expect_locator( $host->locator('#copySpectateBtn'),    'to_be_hidden' );
    expect_locator( $host->locator('#copyWatchInGameBtn'), 'to_have_attribute', 'hidden', '' );
    expect_locator( $host->locator('#roomRoleHelp'),       'to_contain_text',   'lobby-only' );
    $room_code = evaluate_js( $host, 'leqra.getState().online.code' );
    $guest =
      main::load( $second, ( ( $url . '?room=' ) . uri_escape_utf8($room_code) ), 'ROOM GUEST', $errors );
    $guest->locator('#pilotName')->fill('ROOM GUEST');
    $guest->locator('#joinRoomBtn')->click();
    wait_js( $guest, '() => !!leqra.getState().online?.connected' );
    expect_locator( $host->locator('#startRoomBtn'), 'to_be_disabled' );
    $guest->locator('#readyBtn')->click();
    expect_locator( $host->locator('#startRoomBtn'), 'to_be_enabled' );
    $host_frames     = [];
    $guest_frames    = [];
    $record_infinity = sub {
        my ( $page, $frames ) = @_;
        my ($listen);
        $listen = sub {
            my ($socket) = @_;
            if ( truth_value( ( substr( $socket->url(), -length('/ws/infinite') ) eq '/ws/infinite' ) ) ) {
                capture_event( $socket, 'framereceived', $frames, '(frame) => frame' );
            }
        };
        capture_socket_event( $page, 'websocket', 'framereceived', $frames, '(frame) => frame' );
    };
    $record_infinity->( $host,  $host_frames );
    $record_infinity->( $guest, $guest_frames );
    my $pending_427 = $host->waitForEvent('websocket');
    $socket = {};
    $host->locator('#startRoomBtn')->click();
    my $event_427 = $Leqra::Browser::HANDLE->await($pending_427);
    $socket->{'value'} = $event_427;
    assert_ok(
        (
            sub {
                my ($socket) = @_;
                return ( substr( $socket->url(), -length('/ws/infinite') ) eq '/ws/infinite' );
            }
        )->($event_427),
        "Unexpected WebSocket event"
    );

    for $page ( @{ [ $host, $guest ] } ) {
        main::expect_pilots( $page, 3 );
        expect_locator( $page->locator('#infiniteStatus'), 'to_be_hidden' );
        $leaders = main::standings($page);
        expect_locator( $leaders,                              'to_contain_text', 'ROOM HOST' );
        expect_locator( $leaders,                              'to_contain_text', 'ROOM GUEST' );
        expect_locator( $leaders,                              'to_contain_text', 'ROOM WING' );
        expect_locator( $page->locator('#infiniteTeamScores'), 'to_contain_text', 'Orcas' );
    }
    expect_locator( $host->locator('#infiniteLocalLoadout'),  'to_be_visible' );
    expect_locator( $guest->locator('#infiniteLocalLoadout'), 'to_be_hidden' );
    main::expect_score_rank( $host, JSON::PP::true );
    main::expect_score_rank($guest);
    for $close_with_escape ( @{ [ JSON::PP::true, JSON::PP::false ] } ) {
        $host->locator('#chatBtn')->click();
        expect_locator( $host->locator('#infiniteArena > #chatPanel'), 'to_be_visible' );
        expect_locator( $host->locator('#chatInput'),                  'to_be_focused' );
        $host->locator('#chatInput')->fill('Draft stays in this test room');
        if ( truth_value($close_with_escape) ) {
            $host->keyboard()->press('Escape');
        }
        else {
            $host->locator('#chatCloseBtn')->click();
        }
        expect_locator( $host->locator('#chatPanel'),      'to_be_hidden' );
        expect_locator( $host->locator('#infiniteCanvas'), 'to_be_focused' );
        my $events_452 = [];
        capture_event( $socket->{'value'}, 'framesent', $events_452, "value => value" );
        $host->keyboard()->down('w');
        wait_event_log(
            $events_452,
            sub {
                my ($frame) = @_;
                return main::is_packet( $frame, 'input', { 'forward' => JSON::PP::true } );
            },
            30000
        );
        $host->keyboard()->up('w');
    }
    $welcome = (
        [
            map {
                my $frame = $_;
                truth_value( main::is_packet( $frame, 'welcome' ) )
                  ? ( decode_json($frame) )
                  : ()
            } @{$host_frames}
        ]->[0] // undef
    );
    $guest_welcome = (
        [
            map {
                my $frame = $_;
                truth_value( main::is_packet( $frame, 'welcome' ) )
                  ? ( decode_json($frame) )
                  : ()
            } @{$guest_frames}
        ]->[0] // undef
    );
    assert_ok( ( !value_eq( $welcome->{'id'}, $welcome->{'localId'} ) ),
        'welcome["id"] != welcome["localId"]' );
    $host->locator('#infiniteCanvas')->focus();
    my $events_459 = [];
    capture_event( $socket->{'value'}, 'framesent', $events_459, "value => value" );
    $host->keyboard()->down('ArrowUp');
    wait_event_log(
        $events_459,
        sub {
            my ($frame) = @_;
            return main::is_packet( $frame, 'input',
                { 'local' => JSON::PP::true, 'forward' => JSON::PP::true } );
        },
        30000
    );
    my $events_461 = [];
    capture_event( $socket->{'value'}, 'framereceived', $events_461, "value => value" );
    $host->keyboard()->up('ArrowUp');
    wait_event_log(
        $events_461,
        sub {
            my ($frame) = @_;
            return (
                do {
                    my $boolean_value = main::is_packet( $frame, 'state' );
                    truth_value($boolean_value)
                      ? scalar(
                        grep {
                            my $pilot = $_;
                            (
                                do {
                                    my $boolean_value = ( value_eq( $pilot->{'id'}, $welcome->{'localId'} ) );
                                    truth_value($boolean_value)
                                      ? ( ( ( $pilot->{'ack'} // 0 ) > 0 ) )
                                      : $boolean_value;
                                }
                            )
                        } @{ decode_json($frame)->{'tanks'} }
                      )
                      : $boolean_value;
                }
            );
        },
        30000
    );
    $drop = sub {
        my ( $page, $paths ) = @_;
        my ($closed);
        $closed = evaluate_js(
            $page, 'paths => gameSockets.filter(socket => {
                if (socket.readyState !== WebSocket.OPEN || !paths.includes(new URL(socket.url).pathname)) return false;
                socket.close();
                return true;
            }).length', $paths
        );
        assert_ok( ( value_eq( $closed, scalar( @{$paths} ) ) ), [ $closed, $paths ] );
    };
    for $paths ( @{ [ ['/ws/infinite'], [ '/ws', '/ws/infinite' ], undef ] } ) {
        $before = scalar( @{$host_frames} );
        my $pending_476 = $host->waitForEvent('websocket');
        if ( truth_value( ( !defined($paths) ) ) ) {
            $host->reload();
        }
        else {
            $drop->( $host, $paths );
        }
        my $event_476 = $Leqra::Browser::HANDLE->await($pending_476);
        assert_ok(
            (
                sub {
                    my ($socket) = @_;
                    return ( substr( $socket->url(), -length('/ws/infinite') ) eq '/ws/infinite' );
                }
            )->($event_476),
            "Unexpected WebSocket event"
        );
        main::expect_pilots( $host, 3 );
        $resumed = (
            [
                map {
                    my $frame = $_;
                    truth_value( main::is_packet( $frame, 'welcome' ) )
                      ? ( decode_json($frame) )
                      : ()
                } @{ array_slice( $host_frames, $before, undef ) }
            ]->[0] // undef
        );
        assert_ok( ( value_eq( ( $resumed->{'resumed'} // undef ), JSON::PP::true ) ), $resumed );
        assert_ok(
            !scalar(
                grep {
                    my $key = $_;
                    !( ( value_eq( $resumed->[$key], $welcome->[$key] ) ) )
                } @{ [ 'id', 'localId', 'seed', 'generation' ] }
            ),
            $resumed
        );
        expect_locator( $host->locator('#infiniteLocalLoadout'), 'to_be_visible' );
    }
    $moderator = (
        truth_value(
            evaluate_js( $host, '() => leqra.getState().online.id === leqra.getState().room.host' )
          )
        ? $host
        : $guest
    );
    $before = scalar( @{$host_frames} );
    my $pending_493 = $host->waitForEvent('websocket');
    evaluate_js(
        $moderator, '() => {
                const seat = leqra.getState().room.players.find(player => player.kind === \'local\');
                const room = gameSockets.find(socket => socket.readyState === WebSocket.OPEN &&
                    new URL(socket.url).pathname === \'/ws\');
                room.send(JSON.stringify({type:\'kick\', target:seat.id, member:seat.member}));
            }'
    );
    my $event_493 = $Leqra::Browser::HANDLE->await($pending_493);
    assert_ok(
        (
            sub {
                my ($socket) = @_;
                return ( substr( $socket->url(), -length('/ws/infinite') ) eq '/ws/infinite' );
            }
        )->($event_493),
        "Unexpected WebSocket event"
    );
    main::expect_pilots( $host, 2 );
    $resumed = (
        [
            map {
                my $frame = $_;
                truth_value( main::is_packet( $frame, 'welcome' ) )
                  ? ( decode_json($frame) )
                  : ()
            } @{ array_slice( $host_frames, $before, undef ) }
        ]->[0] // undef
    );
    assert_ok(
        (
            do {
                my $boolean_value = ( value_eq( ( $resumed->{'resumed'} // undef ), JSON::PP::true ) );
                truth_value($boolean_value)
                  ? ( !( contains_value( $resumed, 'localId' ) ) )
                  : $boolean_value;
            }
        ),
        $resumed
    );
    assert_ok(
        !scalar(
            grep {
                my $key = $_;
                !( ( value_eq( $resumed->[$key], $welcome->[$key] ) ) )
            } @{ [ 'id', 'seed', 'generation' ] }
        ),
        $resumed
    );
    expect_locator( $host->locator('#infiniteLocalLoadout'), 'to_be_hidden' );
    $outsider = main::load( $public, $url, 'PUBLIC SOLO', $errors );
    $outsider->locator('#startRoomBtn')->click();
    main::expect_pilots( $outsider, 1 );
    expect_locator( $outsider->locator('#infiniteStatus'), 'to_be_hidden' );
    $leaders = main::standings($outsider);
    expect_locator( $leaders, 'to_contain_text',     'PUBLIC SOLO' );
    expect_locator( $leaders, 'not_to_contain_text', 'ROOM HOST' );
    $guest->locator('#pauseBtn')->click();
    $guest->locator('#infiniteExit')->click();
    expect_locator( $guest->locator('#infiniteArena'), 'to_be_hidden' );
    main::expect_pilots( $host, 1 );
    my $pending_518 = $guest->waitForEvent('websocket');
    $drop->( $guest, ['/ws'] );
    my $event_518 = $Leqra::Browser::HANDLE->await($pending_518);
    assert_ok(
        (
            sub {
                my ($socket) = @_;
                return ( substr( $socket->url(), -length('/ws') ) eq '/ws' );
            }
        )->($event_518),
        "Unexpected WebSocket event"
    );
    wait_js( $guest, '() => !!leqra.getState().online?.connected' );
    expect_locator( $guest->locator('#infiniteArena'), 'to_be_hidden' );
    $before = scalar( @{$guest_frames} );
    $guest->locator('#readyBtn:visible, #startRoomBtn:visible')->click();
    main::expect_pilots( $guest, 2 );
    $rejoined = (
        [
            map {
                my $frame = $_;
                truth_value( main::is_packet( $frame, 'welcome' ) )
                  ? ( decode_json($frame) )
                  : ()
            } @{ array_slice( $guest_frames, $before, undef ) }
        ]->[0] // undef
    );
    assert_ok(
        (
            do {
                my $boolean_value =
                  ( !value_eq( $rejoined->{'id'}, $guest_welcome->{'id'} ) );
                truth_value($boolean_value)
                  ? ( !truth_value( ( $rejoined->{'resumed'} // undef ) ) )
                  : $boolean_value;
            }
        ),
        $rejoined
    );
    my $tuple_528_8 = (
        truth_value(
            evaluate_js( $host, '() => leqra.getState().online.id === leqra.getState().room.host' )
          )
        ? [ $host, $guest ]
        : [ $guest, $host ]
    );
    $moderator = $tuple_528_8->[0];
    $other     = $tuple_528_8->[1];
    $other->locator('#pauseBtn')->click();
    $other->locator('#infiniteControlsBtn')->click();
    expect_locator( $other->locator('#controlsDialog'), 'to_be_visible' );
    $other->locator('#openIntroTour')->click();
    expect_locator( $other->locator('#introTourDialog'), 'to_be_visible' );
    $moderator->locator('#pauseBtn')->click();
    $moderator->locator('#infiniteExit')->click();
    $moderator->locator('#endInfinityBtn')->click();
    $moderator->locator('#actionConfirmAccept')->click();
    expect_locator( $other->locator('#infiniteArena'),            'to_be_hidden' );
    expect_locator( $other->locator('#infinitePauseMenu'),        'to_be_hidden' );
    expect_locator( $other->locator('#controlsDialog'),           'to_be_hidden' );
    expect_locator( $other->locator('#introTourDialog'),          'to_be_hidden' );
    expect_locator( $other->locator('.main-grid > #gameSidebar'), 'to_have_count',   1 );
    expect_locator( $other->locator('#readyBtn'),                 'to_contain_text', 'READY' );
    expect_locator( $moderator->locator('#endInfinityBtn'),       'to_be_hidden' );
    assert_ok(
        !scalar(
            grep {
                my $page = $_;
                !( evaluate_js( $page, 'leqra.getState().online.connected' ) )
            } @{ [ $host, $guest ] }
        ),
        'all(page.evaluate("leqra.getState().online.connected") for page in (host, guest))'
    );
    main::expect_pilots( $outsider, 1 );
    $public->close();
    $second->close();
    $first->close();
    print(
        join( " ",
'PASS private teams, P2 input and removal, automatic reconnect and reload, public isolation, exit and end'
        ),
        "\n"
    );
}

sub check_rank_outside_leaders {
    my ( $browser, $url, $errors, $screenshot_dir ) = @_;
    my ( $context, $leaders, $matches_authority, $page, $pause );
    $screenshot_dir //= undef;
    $context = $browser->newContext();
    $context->addInitScript( '
            localStorage.setItem(\'leqra.local2Name\', \'RANKED P2\');
            window.WebSocket = class extends WebSocket {
                constructor(...args) {
                    super(...args);
                    if (!window.captureRankGame || new URL(args[0],location.href).pathname !== \'/ws/infinite\') return;
                    window.rankGameSocket = this;
                    this.addEventListener(\'message\', event => {
                        const packet = JSON.parse(event.data);
                        if (packet.type === \'welcome\') this.rankWelcome = packet;
                        if (packet.type === \'state\') this.rankState = packet;
                    });
                }
            };
        ' );
    $page = main::load( $context, $url, 'RANKED PILOT', $errors );
    $page->locator('#roomPlayers > summary')->click();
    $page->locator('#addLocalBtn')->click();
    expect_locator( $page->locator('#roomRoster'), 'to_contain_text', 'RANKED P2' );
    evaluate_js(
        $page, 'async () => {
            const url = new URL(\'/ws/infinite\', location.href);
            url.protocol = location.protocol === \'https:\' ? \'wss:\' : \'ws:\';
            window.rankPeers = [];
            await Promise.all(Array.from({length:12}, (_, index) => new Promise((resolve, reject) => {
                const socket = new WebSocket(url);
                rankPeers.push(socket);
                const timer = setTimeout(() => reject(Error(\'Rank fixture pilot did not join\')), 5000);
                socket.onopen = () => socket.send(JSON.stringify({type:\'join\',version:leqra.version,name:\'RANK PEER \'+index}));
                socket.onerror = () => {clearTimeout(timer);reject(Error(\'Rank fixture connection failed\'));};
                socket.onmessage = event => {
                    const packet = JSON.parse(event.data);
                    if (packet.type === \'welcome\') {clearTimeout(timer);resolve();}
                    else if (packet.type === \'error\') {clearTimeout(timer);reject(Error(packet.message));}
                };
            })));
            window.captureRankGame = true;
        }'
    );
    $page->locator('#startRoomBtn')->click();
    main::expect_pilots( $page, 14 );
    main::expect_score_rank( $page, JSON::PP::true );
    $leaders = main::standings($page);
    expect_locator( $page->locator('#infiniteLeaderboardTitle'), 'to_have_text',  'LEADERBOARD' );
    expect_locator( $leaders->locator('li'),                     'to_have_count', 12 );
    evaluate_js( $page, 'window.rankBoard = document.querySelector(\'#infiniteLeaderboard\')' );
    $matches_authority = '() => {
            const socket=window.rankGameSocket, state=socket?.rankState, welcome=socket?.rankWelcome;
            if (!state || !welcome || welcome.localId == null) return false;
            const ids=[welcome.id,welcome.localId], locals=ids.map(id=>state.tanks.find(tank=>tank.id===id));
            if (locals.some(tank=>!tank || !Number.isSafeInteger(tank.rank) || tank.rank<=10)) return false;
            const top=state.leaderboard.slice(0,10);
            if (top.length!==10 || new Set(top.map(tank=>tank.id)).size!==10 || top.some(tank=>ids.includes(tank.id))) return false;
            const canonical=color=>{const node=document.createElement(\'span\');node.style.color=color;return node.style.color;};
            const expected=[...top.map((tank,i)=>({tank,rank:i+1,local:0})),
                ...locals.map((tank,i)=>({tank,rank:tank.rank,local:i+1})).sort((a,b)=>a.rank-b.rank)];
            const rows=[...document.querySelectorAll(\'#infiniteLeaderboard > li\')];
            return rows.length===12 && expected.every(({tank,rank,local},i)=>{
                const row=rows[i], label=tank.name+(local?\' (P\'+local+\')\':\'\');
                return row.value===rank && row.querySelector(\'span\')?.textContent===label &&
                    row.querySelector(\'strong\')?.textContent===String(tank.score) &&
                    (row.dataset.local||\'\')===(local?\'p\'+local:\'\') &&
                    row.classList.contains(\'off-board-local\')===!!local &&
                    getComputedStyle(row).color===canonical(leqraInfinityArt.colors[tank.colorIndex]) &&
                    (!local || row.style.getPropertyValue(\'--local-highlight\')===leqraInfinityArt.colors[tank.colorIndex]);
            }) && rows.filter(row=>row.dataset.local===\'p1\').length===1 && rows.filter(row=>row.dataset.local===\'p2\').length===1;
        }';
    wait_js( $page, $matches_authority );

    if ( truth_value( ( defined($screenshot_dir) ) ) ) {
        $page->screenshot(
            {
                path => format_value(
                    $screenshot_dir->child( ( $browser->browserType()->name() . '-rank-active.png' ) )
                )
            }
        );
    }
    $page->locator('#pauseBtn')->click();
    $pause = $page->locator('#infinitePauseMenu');
    expect_locator( $pause, 'to_be_visible' );
    expect_locator( $pause->locator('#infinitePauseSidebar #infiniteLeaderboard > li'), 'to_have_count', 12 );
    assert_ok(
        evaluate_js( $page, 'document.querySelector(\'#infiniteLeaderboard\') === rankBoard' ),
        'page.evaluate("document.querySelector(\'#infiniteLeaderboard\') === rankBoard")'
    );
    expect_locator( $page->locator('#infiniteLeaderboardPanel'), 'to_have_count', 1 );
    wait_js( $page, $matches_authority );

    if ( truth_value( ( defined($screenshot_dir) ) ) ) {
        $page->screenshot(
            {
                path => format_value(
                    $screenshot_dir->child( ( $browser->browserType()->name() . '-rank-paused.png' ) )
                )
            }
        );
    }
    $pause->locator('#infiniteResumeBtn')->click();
    expect_locator( $pause, 'to_be_hidden' );
    expect_locator( $page->locator('.infinite-stage #infiniteLeaderboard > li'), 'to_have_count', 12 );
    assert_ok(
        evaluate_js( $page, 'document.querySelector(\'#infiniteLeaderboard\') === rankBoard' ),
        'page.evaluate("document.querySelector(\'#infiniteLeaderboard\') === rankBoard")'
    );
    wait_js( $page, $matches_authority );
    $page->locator('#pauseBtn')->click();
    $page->locator('#infiniteExit')->click();
    evaluate_js( $page, 'rankPeers.forEach(socket => socket.close())' );
    $context->close();
    print(
        join( " ",
'PASS top ten plus both local ranks, scores, and colors stay correct in active and paused Infinity'
        ),
        "\n"
    );
}

sub check_mobile_ranks {
    my ( $browser, $url, $errors ) = @_;
    my ( $colors, $context, $current, $item, $layout, $page, $previous, $split, $width );
    for $width ( @{ [ 320, 390 ] } ) {
        $context = $browser->newContext(
            {
                viewport => { 'width' => $width, 'height' => 844 },
                isMobile => JSON::PP::true,
                hasTouch => JSON::PP::true
            }
        );
        $page = main::load( $context, $url, 'RANK PILOT', $errors );
        $page->locator('#startRoomBtn')->tap();
        main::expect_pilots( $page, 1 );
        main::expect_score_rank($page);
        expect_locator( $page->locator('#infiniteLeaderboardTitle'), 'to_have_text', 'LEADERBOARD' );
        for $split ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
            if ( truth_value($split) ) {
                $page->locator('#pauseBtn')->tap();
                $page->locator('#infiniteExit')->tap();
                main::select_room_infinity($page);
                $page->locator('#roomPlayers > summary')->tap();
                $page->locator('#addLocalBtn')->tap();
                $page->locator('#copyInviteBtn')->tap();
                wait_js( $page, '() => !!leqra.getState().online?.connected' );
                $page->locator('#startRoomBtn')->tap();
                main::expect_pilots( $page, 2 );
                main::expect_score_rank( $page, JSON::PP::true );
                expect_locator( $page->locator('#infiniteLeaderboardTitle'), 'to_have_text', 'LEADERBOARD' );
                $colors = evaluate_js(
                    $page, '() => {
                        const canonical=color=>{const node=document.createElement(\'span\');node.style.color=color;return node.style.color;};
                        return {actual:[...document.querySelectorAll(\'#infiniteKills .infinite-personal-score\')].map(node=>getComputedStyle(node).color),expected:leqraInfinityArt.colors.slice(0,2).map(canonical)};
                    }'
                );
                assert_ok( ( value_eq( $colors->{'actual'}, $colors->{'expected'} ) ), $colors );
            }
            $layout = evaluate_js(
                $page->locator('#infiniteArena .infinite-statusbar'),
                'header => {
                    const box = node => {const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom};};
                    return {header:box(header),title:box(header.querySelector(\'.arena-title\')),fps:box(header.querySelector(\'.fps-indicator\')),button:box(header.querySelector(\'.infinite-scoreboard-toggle\')),scores:box(header.querySelector(\'.infinite-personal-scores\')),rows:[...header.querySelectorAll(\'.infinite-personal-score\')].map(box),width:innerWidth,overflow:header.scrollWidth>header.clientWidth};
                }'
            );
            assert_ok(
                (
                    do {
                        my $boolean_value =
                          ( !truth_value( $layout->{'overflow'} ) );
                        truth_value($boolean_value)
                          ? ( ( $layout->{'header'}->{'right'} <= ( $width + 1 ) ) )
                          : $boolean_value;
                    }
                ),
                $layout
            );
            assert_ok(
                (
                    (
                        abs(
                            (
                                (
                                    (
                                        ( $layout->{'fps'}->{'left'} + $layout->{'fps'}->{'right'} ) -
                                          $layout->{'header'}->{'left'}
                                    ) - $layout->{'header'}->{'right'}
                                ) / 2
                            )
                        ) <= 1
                    )
                ),
                $layout
            );
            assert_ok( ( ( $layout->{'title'}->{'right'} <= ( $layout->{'fps'}->{'left'} + 1 ) ) ), $layout );
            assert_ok( ( ( $layout->{'fps'}->{'right'} <= ( $layout->{'button'}->{'left'} + 1 ) ) ),
                $layout );
            assert_ok( ( ( $layout->{'scores'}->{'top'} >= ( $layout->{'button'}->{'bottom'} - 1 ) ) ),
                $layout );
            for my $item (
                @{
                    [
                        map {
                            my $i = $_;
                            [ $layout->{'rows'}->[$i], array_slice( $layout->{'rows'}, 1, undef )->[$i] ]
                        } 0 .. min( $#{ $layout->{'rows'} },
                            $#{ array_slice( $layout->{'rows'}, 1, undef ) } )
                    ]
                }
              )
            {
                my $tuple_677_20 = $item;
                my $previous     = $tuple_677_20->[0];
                my $current      = $tuple_677_20->[1];
                assert_ok( ( ( $previous->{'bottom'} <= ( $current->{'top'} + 1 ) ) ), $layout );
            }
            assert_ok(
                !scalar(
                    grep {
                        my $item = $_;
                        !(
                            (
                                   ( 0 <= $item->{'left'} )
                                && ( $item->{'left'} < $item->{'right'} )
                                && ( $item->{'right'} <= ( $width + 1 ) )
                            )
                        )
                    } @{ $layout->{'rows'} }
                ),
                $layout
            );
            assert_ok(
                evaluate_js(
                    $page->locator('#infiniteArena'),
                    'node => node.scrollWidth <= node.clientWidth + 1'
                ),
                'page.locator("#infiniteArena").evaluate("node => node.scrollWidth <= node.clientWidth + 1")'
            );
            assert_ok(
                evaluate_js(
                    $page->locator('#gameHeader'),
                    'node => node.scrollWidth <= node.clientWidth + 1'
                ),
                'page.locator("#gameHeader").evaluate("node => node.scrollWidth <= node.clientWidth + 1")'
            );
        }
        $context->close();
    }
    print( join( " ", 'PASS solo and private P2 ranks fit 320px and 390px online headers' ), "\n" );
}

sub check_scoreboard_titles {
    my ( $browser, $url, $errors, $screenshot_dir ) = @_;
    my (
        $bounds,  $button,         $context,  $empty, $height,
        $index,   $page,           $paired,   $panel, $populated,
        $preview, $preview_button, $snapshot, $touch, $width
    );
    $screenshot_dir //= undef;
    for my $item ( @{ [ [ 1280, 900, JSON::PP::false ], [ 390, 844, JSON::PP::true ] ] } ) {
        my $tuple_686_8 = $item;
        my $width       = $tuple_686_8->[0];
        my $height      = $tuple_686_8->[1];
        my $touch       = $tuple_686_8->[2];
        for my $paired ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
            my $context = $browser->newContext(
                {
                    viewport       => { 'width' => $width, 'height' => $height },
                    isMobile       => $touch,
                    hasTouch       => $touch,
                    serviceWorkers => 'block'
                }
            );
            my $snapshot = { 'players' => 0, 'tankCount' => 0, 'leaders' => [] };
            fixture_response( $context, $url, '/api/infinity', $snapshot, 'application/json' );
            my $page = main::load( $context, $url, 'TITLE PILOT', $errors );
            for my $populated ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
                if ( truth_value($populated) ) {
                    $snapshot = {
                        'players'   => 2,
                        'tankCount' => 10,
                        'leaders'   => [
                            map {
                                my $index = $_;
                                {
                                    'id'         => ( $index + 1 ),
                                    'name'       => ( 'Pilot ' . ( $index + 1 ) ),
                                    'colorIndex' => ( $index % 8 ),
                                    'score'      => ( 20 - $index ),
                                    'rank'       => ( $index + 1 )
                                }
                            } @{ [ 0 .. 10 - 1 ] }
                        ]
                    };
                    fixture_response( $context, $url, '/api/infinity', $snapshot, 'application/json' );
                    $page->reload();
                    wait_js( $page, '() => !!window.leqraInfinity' );
                }
                if ( truth_value($paired) ) {
                    evaluate_js( $page->locator('#roomPlayers'), 'node => node.open = true' );
                    if ( truth_value( $page->locator('#addLocalBtn')->isEnabled() ) ) {
                        $page->locator('#addLocalBtn')->click();
                    }
                    expect_locator( $page->locator('#infinityPreviewScores .infinite-personal-score'),
                        'to_have_count', 2 );
                }
                my $preview_button = $page->locator('#infinityPreviewScoreboardBtn');
                $preview_button->click();
                my $preview = $page->locator('#infinityPreviewScoreboard');
                expect_locator( $preview, 'to_be_visible' );
                expect_locator( $preview_button, 'to_have_attribute', 'aria-expanded', 'true' );
                (
                      truth_value($populated)
                    ? expect_locator( $preview->locator('summary'), 'to_be_visible' )
                    : expect_locator( $preview->locator('summary'), 'to_be_hidden' )
                );
                my $bounds = evaluate_js(
                    $preview, 'panel => {
                        const box = node => node.getBoundingClientRect();
                        return {top:box(panel).top,headerBottom:box(document.querySelector(\'#infinityPreviewBar\')).bottom};
                    }'
                );
                assert_ok( ( ( $bounds->{'top'} >= $bounds->{'headerBottom'} ) ), $bounds );

                if ( truth_value($populated) ) {
                    expect_locator( $preview->locator('summary'), 'to_have_text', 'LEADERBOARD' );
                    $preview->locator('summary')->click();
                    expect_locator( $preview, 'to_be_hidden' );
                    expect_locator( $preview_button, 'to_have_attribute', 'aria-expanded', 'false' );
                    $preview_button->click();
                    $preview->locator('summary')->press('Space');
                    expect_locator( $preview,        'to_be_hidden' );
                    expect_locator( $preview_button, 'to_have_attribute', 'aria-expanded', 'false' );
                    expect_locator( $preview_button, 'to_be_focused' );
                }
                else {
                    expect_locator( $preview->locator('ol'), 'to_be_hidden' );
                    expect_locator( $preview->locator('p'), 'to_have_text', 'No tanks are playing yet.' );
                    my $empty = evaluate_js(
                        $preview->locator('p'), 'note => {
                            const r=note.getBoundingClientRect(),p=note.parentElement.getBoundingClientRect(),s=getComputedStyle(note);
                            return {center:Math.abs((r.top+r.bottom-p.top-p.bottom)/2),align:s.textAlign,border:s.borderTopWidth};
                        }'
                    );
                    assert_ok(
                        (
                            do {
                                my $boolean_value =
                                  ( ( $empty->{'center'} <= 1 ) );
                                truth_value($boolean_value)
                                  ? do {
                                    my $boolean_value = ( value_eq( $empty->{'align'}, 'center' ) );
                                    truth_value($boolean_value)
                                      ? ( value_eq( $empty->{'border'}, '0px' ) )
                                      : $boolean_value;
                                  }
                                  : $boolean_value;
                            }
                        ),
                        $empty
                    );
                    $preview_button->click();
                }
            }
            evaluate_js(
                $page, 'paired => leqraInfinity.start(\'online\', {
                    name:\'TITLE PILOT\', ...(paired ? {localName:\'WINGMATE\'} : {})
                })', $paired
            );
            expect_locator( $page->locator('#infiniteOnlineCount'),
                'to_have_text', regex('^[1-9]\\d* online$') );
            my $button = $page->locator('#infiniteScoreboardBtn');
            $button->click();
            my $panel = $page->locator('#infiniteLeaderboardPanel');
            expect_locator( $panel->locator('summary'), 'to_be_visible' );
            expect_locator( $panel->locator('summary'), 'to_have_text', 'LEADERBOARD' );
            $bounds = evaluate_js(
                $panel, 'panel => {
                    const box=node=>node.getBoundingClientRect();
                    return {top:box(panel).top,headerBottom:box(document.querySelector(\'#infiniteStatusbar\')).bottom,
                        scoresBottom:box(document.querySelector(\'#infiniteKills\')).bottom};
                }'
            );
            assert_ok(
                ( ( $bounds->{'top'} >= max( $bounds->{'headerBottom'}, $bounds->{'scoresBottom'} ) ) ),
                $bounds );

            if (
                truth_value(
                    (
                        do {
                            my $boolean_value = ( defined($screenshot_dir) );
                            truth_value($boolean_value)
                              ? $paired
                              : $boolean_value;
                        }
                    )
                )
              )
            {
                $page->screenshot(
                    {
                        path => format_value(
                            $screenshot_dir->child(
                                ( $browser->browserType()->name() . '-' . $width . '-active-title.png' )
                            )
                        )
                    }
                );
            }
            $panel->locator('summary')->click();
            expect_locator( $panel, 'to_be_hidden' );
            expect_locator( $button, 'to_have_attribute', 'aria-expanded', 'false' );
            $button->click();
            expect_locator( $button, 'to_have_attribute', 'aria-expanded', 'true' );
            $panel->locator('summary')->press('Space');
            expect_locator( $panel,  'to_be_hidden' );
            expect_locator( $button, 'to_have_attribute', 'aria-expanded', 'false' );
            expect_locator( $button, 'to_be_focused' );
            $button->click();
            $page->locator('#pauseBtn')->click();
            expect_locator( $page->locator('#infinitePauseSidebar #infiniteLeaderboardPanel summary'),
                'to_have_text', 'LEADERBOARD' );
            expect_locator( $panel->locator('summary'), 'to_be_visible' );
            $page->locator('#infiniteResumeBtn')->click();
            expect_locator( $panel->locator('summary'), 'to_be_visible' );
            expect_locator( $button, 'to_have_attribute', 'aria-expanded', 'true' );
            $context->close();
        }
    }
    print(
        join( " ",
'PASS titled active/populated preview scoreboards stay below scores and toggle with synchronized buttons; empty previews remain a centered message'
        ),
        "\n"
    );
}

sub check_control_alignment {
    my ( $browser, $errors, $url ) = @_;
    my ( $a, $b, $context, $group, $height, $index, $layout, $page, $paired, $remapped, $source_url, $width );
    $url //= undef;
    $index      = path($0)->absolute->parent(2)->child('web/index.html');
    $source_url = (
        do {
            my $boolean_value = $url;
            truth_value($boolean_value)
              ? $boolean_value
              : URI::file->new_abs( "" . $index )->as_string;
        }
    );
    $context = $browser->newContext(
        {
            viewport       => { 'width' => 1280, 'height' => 900 },
            serviceWorkers => 'block'
        }
    );
    $page = main::load( $context, $source_url, 'SOLO PILOT', $errors );
    evaluate_js( $page,
        'leqraInfinity.start(\'offline\',{name:\'SOLO PILOT\',roomRules:{infinityRandomBots:false}})' );
    expect_locator( $page->locator('#infiniteControlsHint .control-pilot'), 'to_have_count', 0 );
    expect_locator( $page->locator('#infiniteLoadouts .loadout-name')->first(),
        'to_have_text', 'SOLO PILOT (P1)' );
    for $width ( @{ [ 1280, 1560, 1720, 900, 640 ] } ) {
        $page->setViewportSize( { 'width' => $width, 'height' => 900 } );
        $layout = evaluate_js(
            $page->locator('#infiniteControlsHint'), 'hint => {
                const box=node=>{const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,height:r.height};};
                const readout=hint.parentElement, loadout=document.querySelector(\'#infiniteLoadouts\');
                return {hint:box(hint),readout:box(readout),loadout:box(loadout),
                    groups:[...hint.querySelectorAll(\'.control-key-group\')].map(box),
                    overflow:document.querySelector(\'#infiniteArena\').scrollWidth>innerWidth};
            }'
        );
        assert_ok( ( !truth_value( $layout->{'overflow'} ) ), $layout );
        assert_ok( ( ( abs( ( $layout->{'hint'}->{'right'} - $layout->{'readout'}->{'right'} ) ) <= 1 ) ),
            $layout );
        assert_ok( ( ( abs( ( $layout->{'groups'}->[0]->{'left'} - $layout->{'hint'}->{'left'} ) ) <= 1 ) ),
            $layout );
        assert_ok( ( ( ( $layout->{'loadout'}->{'right'} + 11 ) <= $layout->{'readout'}->{'left'} ) ),
            $layout );
        assert_ok( ( ( ( $layout->{'loadout'}->{'right'} - $layout->{'loadout'}->{'left'} ) >= 239 ) ),
            $layout );
        assert_ok( ( value_eq( scalar( @{ $layout->{'groups'} } ), 7 ) ), $layout );

        if ( truth_value( ( ( $width >= 1280 ) ) ) ) {
            assert_ok(
                (
                    (
                        (
                            max( @{ [ map { my $group = $_; $group->{'top'} } @{ $layout->{'groups'} } ] } )
                              - min(
                                @{ [ map { my $group = $_; $group->{'top'} } @{ $layout->{'groups'} } ] }
                              )
                        ) <= 1
                    )
                ),
                $layout
            );
            assert_ok(
                (
                    (
                        $layout->{'hint'}->{'height'} <= (
                            max(
                                @{
                                    [
                                        map {
                                            my $group = $_;
                                            $group->{'height'}
                                        } @{ $layout->{'groups'} }
                                    ]
                                }
                            ) + 1
                        )
                    )
                ),
                $layout
            );
        }
    }
    expect_locator( $page->locator('#infiniteControlsHint .control-key-group')->nth(4)->locator('kbd'),
        'to_have_text', [ 'Q', 'C', 'SPACE', 'ENTER' ] );
    evaluate_js(
        $page, '() => {
            leqraInfinity.close(); leqraInfinity.start(\'offline\',{name:\'REMAP PILOT\',roomRules:{infinityRandomBots:false},bindings:[
                {forward:\'KeyI\',reverse:\'KeyS\',left:\'KeyA\',right:\'KeyD\',fire:\'KeyZ\',fireAlt:\'KeyC\'},
                {forward:\'KeyU\',reverse:\'ArrowDown\',left:\'ArrowLeft\',right:\'ArrowRight\',fire:\'Space\',fireAlt:\'Enter\'}
            ]});
        }'
    );
    $page->setViewportSize( { 'width' => 1720, 'height' => 900 } );
    expect_locator( $page->locator('#infiniteControlsHint .control-pilot'), 'to_have_count', 0 );
    expect_locator( $page->locator('#infiniteLoadouts .loadout-name')->first(),
        'to_have_text', 'REMAP PILOT (P1)' );
    expect_locator( $page->locator('#infiniteControlsHint .control-key-group')->first()->locator('kbd'),
        'to_have_text', [ 'I', 'U' ] );
    expect_locator( $page->locator('#infiniteControlsHint .control-key-group')->nth(4)->locator('kbd'),
        'to_have_text', [ 'Z', 'C', 'SPACE', 'ENTER' ] );
    assert_ok(
        evaluate_js(
            $page->locator('#infiniteControlsHint'),
'node=>new Set([...node.querySelectorAll(\'.control-key-group\')].map(group=>group.getBoundingClientRect().top)).size===1'
        ),
'page.locator(\'#infiniteControlsHint\').evaluate("node=>new Set([...node.querySelectorAll(\'.control-key-group\')].map(group=>group.getBoundingClientRect().top)).size===1")'
    );
    $context->close();
    print(
        join( " ",
'PASS solo keyboard aliases and both mouse hints fit one row on wide screens and wrap safely on narrow screens'
        ),
        "\n"
    );

    for $remapped ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
        $context = $browser->newContext(
            {
                viewport       => { 'width' => 1280, 'height' => 900 },
                serviceWorkers => 'block'
            }
        );
        $page = main::load( $context, $source_url, 'SHORT', $errors );
        evaluate_js(
            $page, 'remapped => leqraInfinity.start(\'offline\', {
                name:\'SHORT\', localName:\'LONGER CO-PILOT\', roomRules:{infinityRandomBots:false},
                ...(remapped ? {bindings:[
                    {forward:\'NumpadMultiply\',reverse:\'NumpadSubtract\',left:\'NumpadDivide\',right:\'ShiftLeft\',fire:\'NumpadEnter\',fireAlt:\'NumpadAdd\'},
                    {forward:\'ArrowUp\',reverse:\'ArrowDown\',left:\'ArrowLeft\',right:\'ArrowRight\',fire:\'Space\',fireAlt:\'Enter\'}
                ]} : {})
            })', $remapped
        );
        expect_locator( $page->locator('#infiniteControlsHint .control-pilot'),
            'to_have_text', [ 'SHORT (P1)', 'LONGER CO-PILOT (P2)' ] );
        for $width ( @{ [ 900, 1000, 1100, 1280, 1560 ] } ) {
            $page->setViewportSize( { 'width' => $width, 'height' => 900 } );
            wait_js(
                $page, '() => {
                    const rows=[...document.querySelectorAll(\'#infiniteControlsHint .control-groups\')];
                    return rows.length===2 && rows.every(row=>[...row.children].slice(0,5).every(group=>group.style.width));
                }'
            );
            $layout = evaluate_js(
                $page->locator('#infiniteControlsHint'), 'hint => {
                    const box=node=>node.getBoundingClientRect();
                    const rows=[...hint.querySelectorAll(\'.control-player\')];
                    return {right:box(hint).right,parentRight:box(hint.parentElement).right,
                        labels:rows.map(row=>box(row.querySelector(\'.control-pilot\')).right),
                        actions:rows.map(row=>[...row.querySelectorAll(\'.control-key-group\')].slice(0,5).map(group=>box(group).left)),
                        overflow:document.querySelector(\'#infiniteArena\').scrollWidth>innerWidth};
                }'
            );
            assert_ok( ( ( abs( ( $layout->{'right'} - $layout->{'parentRight'} ) ) <= 1 ) ),       $layout );
            assert_ok( ( ( abs( ( $layout->{'labels'}->[0] - $layout->{'labels'}->[1] ) ) <= 1 ) ), $layout );
            assert_ok( ( !truth_value( $layout->{'overflow'} ) ),                                   $layout );
            assert_ok(
                !scalar(
                    grep {
                        my ( $a, $b ) = @{$_};
                        !( ( ( abs( ( $a - $b ) ) <= 1 ) ) )
                      } @{
                        [
                            map { my $i = $_; [ $layout->{'actions'}->[$i] ] }
                              0 .. min( $#{ $layout->{'actions'} } )
                        ]
                      }
                ),
                $layout
            );
        }
        $context->close();
    }
    print(
        join( " ",
'PASS paired hints stay right anchored with aligned labels and actions through wrapping and long remaps'
        ),
        "\n"
    );
    for my $item ( @{ [ [ 320, 568 ], [ 390, 844 ], [ 844, 390 ] ] } ) {
        my $tuple_841_8 = $item;
        my $width       = $tuple_841_8->[0];
        my $height      = $tuple_841_8->[1];
        for my $paired ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
            my $context = $browser->newContext(
                {
                    viewport       => { 'width' => $width, 'height' => $height },
                    isMobile       => JSON::PP::true,
                    hasTouch       => JSON::PP::true,
                    serviceWorkers => 'block'
                }
            );
            my $page = main::load( $context, $source_url, 'TOUCH PILOT', $errors );
            evaluate_js(
                $page,
'paired=>leqraInfinity.start(\'offline\',{name:\'TOUCH PILOT\',...(paired?{localName:\'TOUCH WING\'}:{}),roomRules:{infinityRandomBots:false}})',
                $paired
            );
            expect_locator( $page->locator('#infiniteControlsHint .control-pilot'),
                'to_have_count', ( truth_value($paired) ? 2 : 0 ) );
            expect_locator( $page->locator('#infiniteLoadouts .loadout-name')->first(),
                'to_have_text', 'TOUCH PILOT (P1)' );
            if ( truth_value($paired) ) {
                expect_locator( $page->locator('#infiniteControlsHint .control-pilot'),
                    'to_have_text', [ 'TOUCH PILOT (P1)', 'TOUCH WING (P2)' ] );
                expect_locator( $page->locator('#infiniteLoadouts .loadout-name')->last(),
                    'to_have_text', 'TOUCH WING (P2)' );
            }
            expect_locator( $page->locator('#infiniteControlsHint'), 'to_be_hidden' );
            assert_ok(
                evaluate_js( $page->locator('#infiniteArena'), 'node=>node.scrollWidth<=node.clientWidth' ),
                'page.locator(\'#infiniteArena\').evaluate(\'node=>node.scrollWidth<=node.clientWidth\')'
            );
            $context->close();
        }
    }
    print(
        join( " ",
'PASS solo hints omit duplicate names while left HUD identities and paired touch labels remain intact'
        ),
        "\n"
    );
}

sub check_shared_header {
    my ( $browser, $url, $errors ) = @_;
    my ( $context, $fixed, $height, $infinite, $measure, $page, $touch, $version, $width );
    for my $item (
        @{
            [
                [ 1280, 900, JSON::PP::false ],
                [ 390,  844, JSON::PP::true ],
                [ 320,  568, JSON::PP::true ],
                [ 844,  390, JSON::PP::true ]
            ]
        }
      )
    {
        my $tuple_857_8 = $item;
        my $width       = $tuple_857_8->[0];
        my $height      = $tuple_857_8->[1];
        my $touch       = $tuple_857_8->[2];
        my $context     = $browser->newContext(
            {
                viewport => { 'width' => $width, 'height' => $height },
                isMobile => $touch,
                hasTouch => $touch
            }
        );
        my $page = main::load( $context, $url, 'HEADER PILOT', $errors );
        $page->locator('#infinityToggleLabel')->click();
        $page->locator('#startRoomBtn')->click();
        wait_js( $page, '() => [\'countdown\',\'playing\'].includes(leqra.getState().phase)' );
        evaluate_js( $page, 'window.originalGameHeader = document.querySelector(\'#gameHeader\')' );
        my $measure = '() => {
                const header=document.querySelector(\'#gameHeader\'),brand=header.querySelector(\'.brand\'),controls=header.querySelector(\'.header-right\');
                const box=node=>{const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height};};
                return {header:box(header),brand:box(brand),controls:box(controls),font:getComputedStyle(header.querySelector(\'.brand-name\')).font,overflow:header.scrollWidth>header.clientWidth};
            }';
        my $fixed = evaluate_js( $page, $measure );
        $page->locator('#pauseBtn')->click();
        $page->locator('#returnRoomBtn')->click();

        if ( truth_value( $page->locator('#actionConfirmAccept')->isVisible() ) ) {
            $page->locator('#actionConfirmAccept')->click();
        }
        wait_js( $page, '() => leqra.getState().phase === \'menu\'' );
        main::select_room_infinity($page);
        $page->locator('#startRoomBtn')->click();
        expect_locator( $page->locator('#infiniteHeader > #gameHeader'), 'to_be_visible' );
        expect_locator( $page->locator('#infiniteArena > #chatPanel'),   'to_be_hidden' );
        assert_ok(
            evaluate_js( $page, 'document.querySelector(\'#gameHeader\') === originalGameHeader' ),
            'page.evaluate("document.querySelector(\'#gameHeader\') === originalGameHeader")'
        );
        my $infinite = evaluate_js( $page, $measure );
        assert_ok( ( value_eq( $fixed, $infinite ) ), [ $fixed, $infinite ] );
        assert_ok(
            (
                do {
                    my $boolean_value =
                      ( !truth_value( $infinite->{'overflow'} ) );
                    truth_value($boolean_value)
                      ? ( ( $infinite->{'header'}->{'right'} <= ( $width + 1 ) ) )
                      : $boolean_value;
                }
            ),
            $infinite
        );
        my $version = evaluate_js( $page, 'leqra.version' );
        expect_locator( $page->locator('#gameHeader .github-link #headerVersion'), 'to_have_text', $version );
        expect_locator( $page->locator('#gameHeader .github-link'),
            'to_have_attribute', 'href', 'https://github.com/nhooyr/leqra' );
        expect_locator( $page->locator('#gameHeader'), 'to_have_count', 1 );
        expect_locator( $page->locator('#pauseBtn'), 'to_be_visible' );
        $page->locator('#roomBtn')->click();
        expect_locator( $page->locator('#infinitePauseMenu'), 'to_be_visible' );
        $page->locator('#infiniteResumeBtn')->click();
        $page->locator('#pauseBtn')->click();
        $page->locator('#infiniteExit')->click();
        expect_locator( $page->locator('.app > #gameHeader'), 'to_be_visible' );
        expect_locator( $page->locator('body > #chatPanel'),  'to_be_hidden' );
        assert_ok(
            evaluate_js( $page, 'document.querySelector(\'#gameHeader\') === originalGameHeader' ),
            'page.evaluate("document.querySelector(\'#gameHeader\') === originalGameHeader")'
        );
        $context->close();
    }
    print( join( " ", 'PASS shared header identity, geometry, source version, controls, and restoration' ),
        "\n" );
}
unless (caller) {
    $parser = {};
    $args   = do {
        my %args =
          ( 'url' => ( ( \%ENV )->{'LEQRA_URL'} // 'http://localhost:8080' ) );
        my $help;
        GetOptions( 'help|h' => \$help )
          or die 'Usage: perl infinity_browser.pl url
';
        if ($help) {
            print 'Usage: perl infinity_browser.pl url
';
            exit 0;
        }
        $args{'url'} = shift @ARGV if @ARGV;
        \%args;
    };
    $url        = ( trim_text( $args->{'url'}, '/', 'rstrip' ) . '/' );
    $errors     = [];
    $playwright = start_playwright();
    $browser    = $playwright->launch(
        type            => 'chrome',
        chromiumSandbox => JSON::PP::true
    );
    eval {
        main::check_public( $browser, $url, $errors );
        main::check_offline( $browser, $errors );
        main::check_audio( $browser, $errors );
        main::check_pause_sidebar( $browser, $url, $errors );
        main::check_private( $browser, $url, $errors );
        main::check_rank_outside_leaders( $browser, $url, $errors );
        main::check_mobile_ranks( $browser, $url, $errors );
        main::check_shared_header( $browser, $url, $errors );
        main::check_control_alignment( $browser, $errors, $url );
        main::check_scoreboard_titles( $browser, $url, $errors );
        1;
    };
    my $caught_error = $@;
    $browser->close();
    die $caught_error if $caught_error;
    assert_ok( ( !truth_value($errors) ), $errors );
}
