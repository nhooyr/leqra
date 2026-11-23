#!/usr/bin/env perl
package Leqra::IntroTour;
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

my ( $args, $browser, $engine, $height, $parser, $parts, $playwright, $query, $target, $touch, $width );

# Check the quick tour in isolated Chromium/WebKit: perl src/tests/intro_tour_browser.pl [server URL].
sub check_buttons {
    my ( $page, $next_label ) = @_;
    my ( $button, $layout );
    expect_locator( $page->locator('#introTourNext'), 'to_have_text', $next_label );
    $layout = inspect_elements(
        $page, '.intro-tour-actions > button', 'buttons =>
        buttons.map(button => {
            const {top, height} = button.getBoundingClientRect();
            return {top, height, shadow: getComputedStyle(button).boxShadow};
        })
    '
    );
    assert_ok(
        (
            do {
                my $boolean_value = ( value_eq( scalar( @{$layout} ), 3 ) );
                truth_value($boolean_value)
                  ? ( ( $layout->[0]->{'height'} >= 44 ) )
                  : $boolean_value;
            }
        ),
        $layout
    );
    assert_ok( !scalar( grep { my $button = $_; !( ( value_eq( $button, $layout->[0] ) ) ) } @{$layout} ),
        $layout );
}

sub check_control_rows {
    my ( $section, $labels ) = @_;
    my ( $first, $rows, $second, $tops );
    $rows = $section->locator('dt');
    expect_locator( $rows, 'to_have_text', $labels );
    $tops = inspect_elements( $section, 'dt', 'rows => rows.map(row => row.getBoundingClientRect().top)' );
    assert_ok(
        !scalar(
            grep {
                my ( $first, $second ) = @{$_};
                !( ( ( $first < $second ) ) )
              } @{
                [
                    map {
                        my $i = $_;
                        [ $tops->[$i], array_slice( $tops, 1, undef )->[$i] ]
                    } 0 .. min( $#{$tops}, $#{ array_slice( $tops, 1, undef ) } )
                ]
              }
        ),
        $tops
    );
}

sub check_tour_labels {
    my ($page) = @_;
    my ( $dialog, $heading_id, $label, $section, $section_id );
    $dialog = $page->locator('#introTourDialog');
    expect_locator( $dialog->locator('#introTourPilot'), 'to_have_count',       0 );
    expect_locator( $dialog,                             'not_to_contain_text', regex( '\\bP[12]\\b', 'i' ) );
    for my $item (
        @{
            [
                [ 'introTourTouch',         'introTourTouchTitle',        'Touch' ],
                [ 'introTourKeyboard',      'introTourKeyboardTitle',     'Keyboard' ],
                [ 'introTourDesktop',       'introTourMouseTitle',        'Mouse' ],
                [ 'introTourTouchFire',     'introTourTouchFireTitle',    'Touch' ],
                [ 'introTourKeyboardFire',  'introTourKeyboardFireTitle', 'Keyboard' ],
                [ 'introTourMouseFireHelp', 'introTourMouseFireTitle',    'Mouse' ]
            ]
        }
      )
    {
        my $tuple_35_8 = $item;
        my $section_id = $tuple_35_8->[0];
        my $heading_id = $tuple_35_8->[1];
        my $label      = $tuple_35_8->[2];
        my $section    = $dialog->locator( ( '#' . $section_id ) );
        expect_locator( $section, 'to_have_attribute', 'aria-labelledby', $heading_id );
        expect_locator( $section->locator( ( '#' . $heading_id ) ), 'to_have_text', $label );
        assert_ok(
            ( !defined( $section->getAttribute('aria-label') ) ),
            'section.get_attribute("aria-label") is None'
        );
    }
}

sub check_touch_tour {
    my ($page) = @_;
    my ($touch);
    $touch = $page->locator('#introTourTouch');
    expect_locator( $touch->getByRole( 'heading', { name => 'Touch' } ), 'to_be_visible' );
    Leqra::IntroTour::check_control_rows( $touch, [ 'Movement', 'Aim' ] );
    expect_locator( $touch->locator('dd'),
        'to_have_text',
        [ 'Drag the left stick to drive and aim.', 'Touch near your tank to aim without moving.' ] );
    expect_locator( $page->locator('#introTourKeyboard'), 'to_be_hidden' );
    expect_locator( $page->locator('#introTourDesktop'),  'to_be_hidden' );
    Leqra::IntroTour::check_tour_labels($page);
}

sub check_fire_tour {
    my ( $page, $touch, $mouse_enabled ) = @_;
    my ( $keyboard, $mouse, $touch_help );
    $mouse_enabled //= JSON::PP::true;
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Fire' );
    Leqra::IntroTour::check_tour_labels($page);
    $touch_help = $page->locator('#introTourTouchFire');
    $keyboard   = $page->locator('#introTourKeyboardFire');
    $mouse      = $page->locator('#introTourMouseFireHelp');

    if ( truth_value($touch) ) {
        expect_locator( $touch_help->getByRole( 'heading', { name => 'Touch' } ), 'to_be_visible' );
        expect_locator( $page->locator('#introTourFireButton'),                   'to_be_visible' );
        expect_locator( $keyboard,                                                'to_be_hidden' );
        expect_locator( $mouse,                                                   'to_be_hidden' );
    }
    else {
        expect_locator( $touch_help,                                               'to_be_hidden' );
        expect_locator( $page->locator('#introTourTouchControls'),                 'to_be_hidden' );
        expect_locator( $keyboard->getByRole( 'heading', { name => 'Keyboard' } ), 'to_be_visible' );
        if ( truth_value($mouse_enabled) ) {
            expect_locator( $mouse->getByRole( 'heading', { name => 'Mouse' } ), 'to_be_visible' );
        }
        else {
            expect_locator( $mouse, 'to_be_hidden' );
        }
    }
}

sub hold_practice_key {
    my ( $page, $key ) = @_;
    $page->keyboard()->down($key);
    eval {
        expect_locator( $page->locator('#introTourNext'), 'to_be_enabled' );
        1;
    };
    my $caught_error = $@;
    $page->keyboard()->up($key);
    die $caught_error if $caught_error;
}

sub drag_practice_stick {
    my ($page) = @_;
    my ( $base, $next_button, $pointer, $session, $stick, $x, $y );
    $stick = $page->locator('#introTourStick');
    $stick->scrollIntoViewIfNeeded();
    $base        = $page->locator('#introTourStickBase')->boundingBox();
    $x           = ( $base->{'x'} + ( $base->{'width'} / 2 ) );
    $y           = ( $base->{'y'} + ( $base->{'height'} / 2 ) );
    $next_button = $page->locator('#introTourNext');

    if ( truth_value( ( value_eq( $page->context()->browser()->browserType()->name(), 'chromium' ) ) ) ) {
        $session = $page->context()->newCDPSession($page);
        eval {
            $session->send(
                'Input.dispatchTouchEvent',
                {
                    'type'        => 'touchStart',
                    'touchPoints' => [ { 'x' => $x, 'y' => $y } ]
                }
            );
            $session->send(
                'Input.dispatchTouchEvent',
                {
                    'type'        => 'touchMove',
                    'touchPoints' => [ { 'x' => ( $x + 35 ), 'y' => $y } ]
                }
            );
            expect_locator( $next_button, 'to_be_enabled' );
            1;
        };
        my $caught_error = $@;
        $session->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
        $session->detach();
        die $caught_error if $caught_error;
    }
    else {
        $pointer = {
            'pointerId'   => 1,
            'pointerType' => 'touch',
            'isPrimary'   => JSON::PP::true,
            'clientY'     => $y
        };
        eval {
            $stick->dispatchEvent( 'pointerdown',
                { %{$pointer}, 'button' => 0, 'buttons' => 1, 'clientX' => $x } );
            $stick->dispatchEvent(
                'pointermove',
                {
                    %{$pointer},
                    'button'  => (-1),
                    'buttons' => 1,
                    'clientX' => ( $x + 35 )
                }
            );
            expect_locator( $next_button, 'to_be_enabled' );
            1;
        };
        my $caught_error = $@;
        $stick->dispatchEvent(
            'pointerup',
            {
                %{$pointer},
                'button'  => 0,
                'buttons' => 0,
                'clientX' => ( $x + 35 )
            }
        );
        die $caught_error if $caught_error;
    }
}

sub practice_frame {
    my ($page) = @_;
    return evaluate_js( $page->locator('#introTourCanvas'),
'canvas => { const {x, y, width, height} = canvas.getBoundingClientRect(); return [x, y, width, height]; }'
    );
}

sub next_practice_step {
    my ($page) = @_;
    my ( $after, $before, $first, $next_button, $second );
    $next_button = $page->locator('#introTourNext');
    $next_button->scrollIntoViewIfNeeded();
    $before = Leqra::IntroTour::practice_frame($page);
    $next_button->click();
    $after = Leqra::IntroTour::practice_frame($page);
    assert_ok(
        !scalar(
            grep {
                my ( $first, $second ) = @{$_};
                !( ( ( abs( ( $first - $second ) ) < 0.5 ) ) )
            } @{ [ map { my $i = $_; [ $before->[$i], $after->[$i] ] } 0 .. min( $#{$before}, $#{$after} ) ]
            }
        ),
        [ $before, $after ]
    );
}

sub advance_drive_practice {
    my ( $page, $touch, $key ) = @_;
    my ( $next_button, $status );
    $key //= 'w';
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Drive and aim' );
    expect_locator( $page->locator('#introTourCanvas'), 'to_be_visible' );
    $next_button = $page->locator('#introTourNext');
    $status      = $page->locator('#introTourPracticeStatus');
    expect_locator( $next_button, 'to_be_disabled' );
    expect_locator( $status, 'to_have_text', 'Move the tank to continue.' );

    if ( truth_value($touch) ) {
        expect_locator( $page->locator('#introTourFireButton'), 'to_be_hidden' );
        Leqra::IntroTour::drag_practice_stick($page);
    }
    else {
        expect_locator( $page->locator('#introTourTouchControls'), 'to_be_hidden' );
        Leqra::IntroTour::hold_practice_key( $page, $key );
    }
    expect_locator( $status, 'to_have_text', 'Tank moved.' );
    Leqra::IntroTour::next_practice_step($page);
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Fire' );
    expect_locator( $page->locator('#introTourBack'),  'to_be_enabled' );
    expect_locator( $next_button,                      'to_be_disabled' );
}

sub fire_in_practice {
    my ( $page, $touch, $key, $mouse ) = @_;
    $mouse //= JSON::PP::false;
    if ( truth_value($touch) ) {
        $page->locator('#introTourFireButton')->tap();
    }
    else {
        if ( truth_value($mouse) ) {
            $page->locator('#introTourCanvas')->click();
        }
        else {
            Leqra::IntroTour::hold_practice_key( $page, $key );
        }
    }
}

sub advance_fire_practice {
    my ( $page, $touch, $key, $mouse ) = @_;
    my ( $next_button, $status );
    $key   //= 'q';
    $mouse //= JSON::PP::false;
    $next_button = $page->locator('#introTourNext');
    $status      = $page->locator('#introTourPracticeStatus');
    expect_locator( $next_button, 'to_be_disabled' );
    expect_locator( $status, 'to_have_text', 'Fire a shot to continue.' );
    Leqra::IntroTour::fire_in_practice( $page, $touch, $key, $mouse );
    expect_locator( $next_button, 'to_be_enabled' );
    expect_locator( $status, 'to_have_text', 'Shot fired.' );
    Leqra::IntroTour::next_practice_step($page);
    expect_locator( $page->locator('#introTourTitle'),    'to_have_text', 'Score a point' );
    expect_locator( $page->locator('#introTourPractice'), 'to_be_visible' );
    expect_locator( $next_button,                         'to_be_disabled' );
}

sub advance_score_practice {
    my ( $page, $touch, $key ) = @_;
    my ( $next_button, $score );
    $key //= 'q';
    $next_button = $page->locator('#introTourNext');
    $score       = $page->locator('#introTourScore');
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Score a point' );
    expect_locator( $page->locator('[data-intro-page="2"]'),
        'to_have_text', 'Destroy the stationary tank to score a point.' );
    expect_locator( $page->locator('#introTourCanvas'),     'to_be_visible' );
    expect_locator( $page->locator('#introTourScorePanel'), 'to_be_visible' );
    expect_locator( $next_button,                           'to_be_disabled' );
    expect_locator( $score,                                 'to_have_text', '0' );
    Leqra::IntroTour::fire_in_practice( $page, $touch, $key );
    expect_locator( $score,                                     'to_have_text', '1' );
    expect_locator( $page->locator('#introTourPracticeStatus'), 'to_be_hidden' );
    expect_locator( $next_button,                               'to_be_enabled' );
    $next_button->click();
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Choose a battle' );
    expect_locator( $page->locator('#introTourPractice'), 'to_be_hidden' );
}

sub check_desktop_tour {
    my ( $page, $mouse_enabled ) = @_;
    my ( $keyboard, $mouse );
    $mouse_enabled //= JSON::PP::true;
    expect_locator( $page->locator('#introTourTouch'), 'to_be_hidden' );
    $keyboard = $page->locator('#introTourKeyboard');
    expect_locator( $keyboard->getByRole( 'heading', { name => 'Keyboard' } ), 'to_be_visible' );
    $mouse = $page->locator('#introTourDesktop');
    if ( truth_value($mouse_enabled) ) {
        expect_locator( $mouse->getByRole( 'heading', { name => 'Mouse' } ), 'to_be_visible' );
    }
    else {
        expect_locator( $mouse, 'to_be_hidden' );
    }
    Leqra::IntroTour::check_tour_labels($page);
}

sub check_sidebar {
    my ( $page, $touch ) = @_;
    my ( $dialog, $last_pickup, $sidebar, $toggle, $touch_instructions );
    $sidebar = $page->locator('#gameSidebar');
    $toggle  = $page->getByRole( 'button', { name => 'Open sidebar' } );
    $dialog  = $page->getByRole( 'dialog', { name => 'Sidebar' } );
    expect_locator( $page->locator('#gameHeader #sidebarDetailsBtn'), 'to_be_visible' );
    expect_locator( $sidebar,                                         'to_be_hidden' );
    expect_locator( $toggle, 'to_have_attribute', 'aria-expanded', 'false' );
    expect_locator( $toggle, 'to_be_in_viewport', { ratio => 1 } );

    if ( truth_value($touch) ) {
        $toggle->tap();
    }
    else {
        $toggle->press('Space');
    }
    expect_locator( $dialog,                          'to_be_visible' );
    expect_locator( $dialog->locator('#gameSidebar'), 'to_be_visible' );
    expect_locator( $toggle,                          'to_have_attribute', 'aria-expanded', 'true' );
    expect_locator( $dialog->locator('.power-row'),   'to_have_count',     10 );
    if ( truth_value($touch) ) {
        $touch_instructions = $dialog->getByText(
'Drag the joystick to drive and aim. Touch near the tank to aim in place. Tap or hold Fire to shoot.'
        );
        expect_locator( $touch_instructions, 'to_be_visible' );
    }
    $last_pickup = $dialog->locator('.power-row')->last();
    $last_pickup->scrollIntoViewIfNeeded();
    expect_locator( $last_pickup, 'to_be_in_viewport', { ratio => 1 } );
    assert_ok(
        evaluate_js( $dialog, 'dialog => dialog.scrollWidth === dialog.clientWidth' ),
        'dialog.evaluate("dialog => dialog.scrollWidth === dialog.clientWidth")'
    );
    if ( truth_value($touch) ) {
        $dialog->getByRole( 'button', { name => 'Close sidebar' } )->tap();
    }
    else {
        $page->keyboard()->press('Escape');
        expect_locator( $toggle, 'to_be_focused' );
    }
    expect_locator( $dialog,  'to_be_hidden' );
    expect_locator( $sidebar, 'to_be_hidden' );
    expect_locator( $toggle,  'to_have_attribute', 'aria-expanded', 'false' );
}

sub check_keycaps {
    my ( $row, $labels ) = @_;
    my ( $key, $keys, $layout );
    $keys = $row->locator('kbd:not(.control-mouse-key)');
    assert_ok( ( value_eq( tally_values( $keys->allTextContents() ), tally_values($labels) ) ),
        $keys->allTextContents() );
    assert_ok(
        ( ( $row->locator('.control-keycaps')->count() > 0 ) ),
        'row.locator(\'.control-keycaps\').count() > 0'
    );
    $layout = inspect_elements(
        $row, 'kbd:not(.control-mouse-key)', 'keys => keys.map(key => {
        const r=key.getBoundingClientRect(),p=key.closest(\'dd\').getBoundingClientRect(),s=getComputedStyle(key);
        return {left:r.left,right:r.right,parentLeft:p.left,parentRight:p.right,height:r.height,font:parseFloat(s.fontSize)};
    })'
    );
    assert_ok(
        !scalar(
            grep {
                my $key = $_;
                !(
                    (
                        do {
                            my $boolean_value = ( ( $key->{'left'} >= ( $key->{'parentLeft'} - 1 ) ) );
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value = ( ( $key->{'right'} <= ( $key->{'parentRight'} + 1 ) ) );
                                truth_value($boolean_value)
                                  ? do {
                                    my $boolean_value =
                                      ( ( $key->{'height'} >= 20 ) );
                                    truth_value($boolean_value)
                                      ? ( ( $key->{'font'} >= 10 ) )
                                      : $boolean_value;
                                  }
                                  : $boolean_value;
                              }
                              : $boolean_value;
                        }
                    )
                )
            } @{$layout}
        ),
        $layout
    );
}

sub check_mouse_symbols {
    my ($page) = @_;
    my ( $selector, $symbol );
    for $selector ( @{ [ '#introTourMouseAim', '#introTourMouseFire' ] } ) {
        $symbol = $page->locator( ( $selector . ' .control-mouse-key' ) );
        expect_locator( $symbol,                                     'to_have_count', 1 );
        expect_locator( $symbol->locator('svg[aria-hidden="true"]'), 'to_have_count', 1 );
        assert_ok(
            ( contains_value( lc( $symbol->getAttribute('aria-label') ), 'mouse' ) ),
            '\'mouse\' in symbol.get_attribute(\'aria-label\').lower()'
        );
    }
}

sub check_roster_tools_order {
    my ($page) = @_;
    my ( $ids, $key, $order );
    $ids = evaluate_js(
        $page->locator('#roomPlayers .room-disclosure-content'),
        'node => [...node.children].map(child=>child.id)'
    );
    $order = [
        map { my $key = $_; array_index( $ids, $key ) } @{
            [
                'rosterTools',    'roomRoleStrip', 'roomP2RoleStrip', 'roomRoster',
                'roomSpectators', 'localControlsNote'
            ]
        }
    ];
    assert_ok(
        (
            do {
                my $boolean_value = ( value_eq( $order->[0], 0 ) );
                truth_value($boolean_value)
                  ? ( value_eq( $order, sorted_values($order) ) )
                  : $boolean_value;
            }
        ),
        $ids
    );
}

sub emulate_controls_device {
    my ( $page, $installed ) = @_;
    $installed //= JSON::PP::false;
    $page->addInitScript(
        replace_text(
            '(() => {
        const query = \'(any-pointer: fine)\';
        const standaloneQuery = \'(display-mode: standalone)\';
        const matchMedia = window.matchMedia.bind(window);
        const pointer = new EventTarget();
        pointer.media = query;
        pointer.matches = matchMedia(query).matches;
        const standalone = Object.assign(new EventTarget(), {media: standaloneQuery, matches: INSTALLED});
        window.matchMedia = media => media === query ? pointer : media === standaloneQuery ? standalone : matchMedia(media);
        window.setTestMouseConnected = connected => {
            if (pointer.matches === connected) return;
            pointer.matches = connected;
            pointer.dispatchEvent(new MediaQueryListEvent(\'change\', {matches: connected, media: query}));
        };
    })();', 'INSTALLED', ( truth_value($installed) ? 'true' : 'false' )
        )
    );
}

sub check_mobile_controls_hardware {
    my ( $browser, $url ) = @_;
    my (
        $action,    $binds,          $check_options, $context, $display_mode, $grid,
        $installed, $ios_standalone, $keyboard,      $mouse,   $page,         $selector
    );
    for my $item (
        @{
            [
                [ JSON::PP::false, JSON::PP::false ],
                [ JSON::PP::true,  JSON::PP::false ],
                [ JSON::PP::false, JSON::PP::true ]
            ]
        }
      )
    {
        my $tuple_285_8    = $item;
        my $display_mode   = $tuple_285_8->[0];
        my $ios_standalone = $tuple_285_8->[1];
        my $installed      = (
            do {
                my $boolean_value = $display_mode;
                truth_value($boolean_value) ? $boolean_value : $ios_standalone;
            }
        );
        my $context = $browser->newContext(
            {
                viewport       => { 'width' => 390, 'height' => 844 },
                isMobile       => JSON::PP::true,
                hasTouch       => JSON::PP::true,
                serviceWorkers => 'block'
            }
        );
        my $page = $context->newPage();
        $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\',\'1\')');
        Leqra::IntroTour::emulate_controls_device( $page, $display_mode );

        if ( truth_value($ios_standalone) ) {
            $page->addInitScript('Object.defineProperty(navigator, \'standalone\', {value: true})');
        }
        $page->goto($url);
        Leqra::IntroTour::open_room_controls($page);
        my $binds    = $page->locator('#controlsBinds');
        my $grid     = $page->locator('#bindingGrid');
        my $keyboard = [
            map { my $selector = $_; $page->locator($selector) } @{
                [
                    '[data-bind="0:forward"]', '[data-bind="1:forward"]',
                    '#controlsKeyboardHelp',   '#resetBindingsBtn'
                ]
            }
        ];
        my $mouse = [
            map {
                my $action = $_;
                $page->locator( ( '#p1Mouse' . $action . 'Enabled' ) )
            } @{ [ 'Aim', 'Fire' ] }
        ];
        $check_options = sub {
            my ( $keyboard_visible, $mouse_visible ) = @_;
            my ( $control, $controls, $visible );
            for my $item (
                @{
                    [
                        [ $keyboard, $keyboard_visible ],
                        [ $mouse,    $mouse_visible ],
                        [
                            [$grid],
                            (
                                do {
                                    my $boolean_value = $keyboard_visible;
                                    truth_value($boolean_value)
                                      ? $boolean_value
                                      : $mouse_visible;
                                }
                            )
                        ]
                    ]
                }
              )
            {
                my $tuple_304_20 = $item;
                my $controls     = $tuple_304_20->[0];
                my $visible      = $tuple_304_20->[1];
                for my $control ( @{$controls} ) {
                    if ( truth_value($visible) ) {
                        expect_locator( $control, 'to_be_visible' );
                    }
                    else {
                        expect_locator( $control, 'to_be_hidden' );
                    }
                }
            }
        };
        $check_options->( JSON::PP::false, JSON::PP::false );
        expect_locator( $binds, 'to_be_hidden' );
        evaluate_js( $page, 'setTestMouseConnected(true)' );
        if ( truth_value($installed) ) {
            expect_locator( $binds->locator(':scope > summary'), 'to_be_visible' );
            assert_ok( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ),
                'not binds.evaluate(\'node => node.open\')' );
            $check_options->( JSON::PP::false, JSON::PP::false );
            Leqra::IntroTour::open_controls_binds($page);
        }
        else {
            expect_locator( $binds, 'to_be_hidden' );
        }
        $check_options->( $installed, $installed );
        evaluate_js( $page, 'setTestMouseConnected(false)' );
        $check_options->( JSON::PP::false, JSON::PP::false );
        expect_locator( $binds, 'to_be_hidden' );
        $page->locator('#controlsDialog')
          ->dispatchEvent( 'keydown', { 'key' => 'Shift', 'code' => 'ShiftLeft' } );
        $page->keyboard()->press('Shift');
        $check_options->( JSON::PP::false, JSON::PP::false );
        expect_locator( $binds, 'to_be_hidden' );
        evaluate_js( $page, 'setTestMouseConnected(true)' );

        if ( truth_value($installed) ) {
            Leqra::IntroTour::open_controls_binds($page);
        }
        $check_options->( $installed, $installed );
        $context->close();
    }
    print(
        join(
            " ",
            (
                    'PASS '
                  . $browser->browserType()->name()
                  . ': mobile browser hides Binds and standalone offers both bindings with a detected pointer'
            )
        ),
        "\n"
    );
}

sub open_room_controls {
    my ($page) = @_;
    my ($launcher);
    $launcher =
      $page->locator('#gameHeader')->getByRole( 'button', { name => 'Controls', exact => JSON::PP::true } );
    expect_locator( $launcher, 'to_have_attribute', 'id', 'roomControlsBtn' );
    expect_locator( $launcher->locator('svg[aria-hidden="true"]'), 'to_have_count', 1 );
    $launcher->click();
    expect_locator( $page->locator('#controlsDialog #openIntroTour + #showcaseBtn'), 'to_be_visible' );
}

sub open_controls_binds {
    my ($page) = @_;
    my ( $binds, $summary );
    $binds   = $page->locator('#controlsBinds');
    $summary = $binds->locator(':scope > summary');
    expect_locator( $summary, 'to_have_text', 'Binds' );
    expect_locator( $summary, 'to_be_visible' );
    if ( truth_value( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ) ) ) {
        $summary->click();
    }
}

sub check_remapped_tour {
    my ( $page, $touch, $screenshot_dir ) = @_;
    my ( $binding, $key );
    $screenshot_dir //= undef;
    if ( truth_value($touch) ) {
        evaluate_js( $page, 'setTestMouseConnected(true)' );
    }
    Leqra::IntroTour::open_room_controls($page);
    Leqra::IntroTour::open_controls_binds($page);
    for my $item ( @{ [ [ '0:forward', 'i' ], [ '0:fire', 'z' ], [ '1:forward', 'u' ] ] } ) {
        my $tuple_359_8 = $item;
        my $binding     = $tuple_359_8->[0];
        my $key         = $tuple_359_8->[1];
        $page->locator( ( ( '[data-bind="' . $binding ) . '"]' ) )->click();
        $page->keyboard()->press($key);
    }
    $page->locator('#p1MouseAimEnabled')->uncheck();
    $page->locator('#p1MouseFireEnabled')->uncheck();
    $page->locator('#openIntroTour')->click();
    if ( truth_value($touch) ) {
        Leqra::IntroTour::check_touch_tour($page);
    }
    else {
        Leqra::IntroTour::check_desktop_tour( $page, JSON::PP::false );
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourMoveKeys'),
            [ 'I', 'A', 'S', 'D', 'U', '←', '↓', '→' ] );
    }
    Leqra::IntroTour::advance_drive_practice( $page, $touch, 'i' );
    Leqra::IntroTour::check_fire_tour( $page, $touch, JSON::PP::false );
    if ( truth_value( ( !truth_value($touch) ) ) ) {
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourFireKeys'),
            [ 'Z', 'C', 'SPACE', 'ENTER' ] );
    }
    Leqra::IntroTour::advance_fire_practice( $page, $touch, 'z', undef );
    Leqra::IntroTour::advance_score_practice( $page, $touch, 'z' );
    $page->locator('#introTourSkip')->click();
    $page->locator('#p1MouseAimEnabled')->check();
    $page->locator('#p1MouseFireEnabled')->check();
    $page->locator('#openIntroTour')->click();
    if ( truth_value($touch) ) {
        Leqra::IntroTour::check_touch_tour($page);
    }
    else {
        Leqra::IntroTour::check_desktop_tour($page);
        Leqra::IntroTour::check_mouse_symbols($page);
    }
    expect_locator( $page->locator('#introTourNext'), 'to_be_disabled' );
    $page->locator('#introTourSkip')->click();
    $page->locator('[data-close-dialog="controlsDialog"]')->click();
    evaluate_js( $page->locator('#roomPlayers'), 'node => node.open = true' );
    Leqra::IntroTour::check_roster_tools_order($page);
    $page->locator('#addLocalBtn')->click();
    Leqra::IntroTour::open_room_controls($page);
    $page->locator('#openIntroTour')->click();

    if ( truth_value($touch) ) {
        Leqra::IntroTour::check_touch_tour($page);
    }
    else {
        Leqra::IntroTour::check_desktop_tour($page);
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourMoveKeys'), [ 'I', 'A', 'S', 'D' ] );
        Leqra::IntroTour::check_mouse_symbols($page);
    }
    assert_ok(
        evaluate_js( $page->locator('#introTourDialog'), 'node => node.scrollWidth <= node.clientWidth' ),
        'page.locator(\'#introTourDialog\').evaluate(\'node => node.scrollWidth <= node.clientWidth\')'
    );
    assert_ok(
        evaluate_js( $page, 'document.documentElement.scrollWidth <= innerWidth' ),
        'page.evaluate(\'document.documentElement.scrollWidth <= innerWidth\')'
    );
    if ( truth_value( ( defined($screenshot_dir) ) ) ) {
        $page->screenshot( { path => format_value($screenshot_dir) } );
    }
    Leqra::IntroTour::advance_drive_practice( $page, $touch, 'i' );
    Leqra::IntroTour::check_fire_tour( $page, $touch );
    if ( truth_value( ( !truth_value($touch) ) ) ) {
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourFireKeys'), [ 'Z', 'C' ] );
    }
    $page->locator('#introTourSkip')->click();
    $page->locator('[data-close-dialog="controlsDialog"]')->click();
}

sub check_public_headers {
    my ( $page, $paired, $screenshot ) = @_;
    my ($check);
    $screenshot //= undef;
    $check = sub {
        my ( $header_id, $title_id ) = @_;
        my ( $item, $layout );
        expect_locator( $page->locator( ( '#' . $title_id ) ), 'to_have_text', 'Public Infinity' );
        $layout = evaluate_js(
            $page->locator( ( '#' . $header_id ) ), 'header => {
            const box=node=>{const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom};};
            const nodes=[header.querySelector(\'h2\'),header.querySelector(\'.fps-indicator\'),header.querySelector(\'.infinite-scoreboard-toggle\')];
            const overlap=(a,b)=>a.left<b.right-1&&b.left<a.right-1&&a.top<b.bottom-1&&b.top<a.bottom-1;
            const bounds=nodes.map(box),r=box(header);
            return {bounds,header:r,overlap:overlap(bounds[0],bounds[1])||overlap(bounds[1],bounds[2]),
                center:Math.abs((bounds[1].left+bounds[1].right-r.left-r.right)/2),overflow:header.scrollWidth>header.clientWidth};
        }'
        );
        assert_ok(
            (
                do {
                    my $boolean_value =
                      ( !truth_value( $layout->{'overlap'} ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value =
                          ( !truth_value( $layout->{'overflow'} ) );
                        truth_value($boolean_value)
                          ? ( ( $layout->{'center'} <= 1 ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            $layout
        );
        assert_ok(
            !scalar(
                grep {
                    my $item = $_;
                    !(
                        (
                            do {
                                my $boolean_value =
                                  ( ( $item->{'left'} >= ( $layout->{'header'}->{'left'} - 1 ) ) );
                                truth_value($boolean_value)
                                  ? ( ( $item->{'right'} <= ( $layout->{'header'}->{'right'} + 1 ) ) )
                                  : $boolean_value;
                            }
                        )
                    )
                } @{ $layout->{'bounds'} }
            ),
            $layout
        );
    };
    $page->locator('#infinityToggle')->check();
    $check->( 'infinityPreviewBar', 'infinityPreviewTitle' );
    evaluate_js(
        $page,
'paired=>leqraInfinity.start(\'online\',{name:document.getElementById(\'roomCallsign\').value,...(paired?{localName:document.getElementById(\'roomP2Callsign\').value}:{})})',
        $paired
    );
    expect_locator( $page->locator('#infiniteOnlineCount'), 'to_have_text', regex('^[1-9]\\d* online$') );
    expect_locator( $page->locator('#infiniteKills .infinite-score-value')->last(),
        'to_have_text', regex('^score: -?\\d+, rank: #[1-9]\\d*$') );
    $check->( 'infiniteStatusbar', 'infiniteArenaTitle' );
    if ( truth_value($screenshot) ) {
        $page->screenshot( { path => format_value($screenshot) } );
    }
    $page->locator('#pauseBtn')->click();
    $page->locator('#infiniteExit')->click();
    $page->locator('#infinityToggle')->uncheck();
}

sub check_mouse_preferences {
    my ( $browser, $url, $width, $height, $touch, $screenshot_dir ) = @_;
    my (
        $aim,           $binds,      $box,         $caption,   $context,     $control,
        $data,          $errors,     $fire,        $geometry,  $item,        $key_binding,
        $keyboard_help, $manual,     $next_button, $off,       $off_caption, $on,
        $on_caption,    $page,       $paired,      $reset_all, $reset_keys,  $reset_layout,
        $shared,        $shared_tip, $solo_tip,    $stored,    $summary,     $tip,
        $tip_text
    );
    $screenshot_dir //= undef;
    $tip_text = 'Hold any fire key to rapid fire.';
    $context  = $browser->newContext(
        {
            viewport       => { 'width' => $width, 'height' => $height },
            isMobile       => $touch,
            hasTouch       => $touch,
            serviceWorkers => 'block'
        }
    );
    $page   = $context->newPage();
    $errors = [];
    capture_event( $page, 'pageerror', $errors, '(error) => String(error)' );
    $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\',\'1\')');
    Leqra::IntroTour::emulate_controls_device( $page, $touch );
    $page->goto($url);
    wait_js( $page, '() => !!window.leqraInfinity' );
    Leqra::IntroTour::open_room_controls($page);
    $reset_all = $page->locator('#resetAllSettingsBtn');
    expect_locator( $reset_all, 'to_be_visible' );
    $reset_layout = evaluate_js(
        $reset_all, 'button => {
            const style = getComputedStyle(button);
            return {last: button.closest(\'.feature-body\').lastElementChild === button,
                color: style.color, border: style.borderTopColor};
        }'
    );
    assert_ok(
        (
            value_eq(
                $reset_layout,
                {
                    'last'   => JSON::PP::true,
                    'color'  => 'rgb(255, 79, 95)',
                    'border' => 'rgb(255, 79, 95)'
                }
            )
        ),
        $reset_layout
    );
    $key_binding   = $page->locator('[data-bind="0:fireAlt"]');
    $keyboard_help = $page->locator('#controlsKeyboardHelp');
    $reset_keys    = $page->locator('#resetBindingsBtn');
    $aim           = $page->locator('#p1MouseAimEnabled');
    $fire          = $page->locator('#p1MouseFireEnabled');
    $binds         = $page->locator('#controlsBinds');
    $summary       = $binds->locator(':scope > summary');

    if ( truth_value($touch) ) {
        expect_locator( $binds, 'to_be_hidden' );
        for $control ( @{ [ $key_binding, $keyboard_help, $reset_keys, $aim, $fire ] } ) {
            expect_locator( $control, 'to_be_hidden' );
        }
    }
    else {
        expect_locator( $summary, 'to_have_text', 'Binds' );
        assert_ok( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ),
            'not binds.evaluate(\'node => node.open\')' );
        expect_locator( $key_binding, 'to_be_hidden' );
        expect_locator( $aim,         'to_be_hidden' );
        Leqra::IntroTour::open_controls_binds($page);
        for $control ( @{ [ $key_binding, $keyboard_help, $reset_keys, $aim, $fire ] } ) {
            expect_locator( $control, 'to_be_visible' );
        }
        $summary->click();
        expect_locator( $key_binding, 'to_be_hidden' );
        expect_locator( $aim,         'to_be_hidden' );
        $summary->click();
        expect_locator( $key_binding, 'to_be_visible' );
        expect_locator( $aim,         'to_be_visible' );
    }
    evaluate_js( $page, 'setTestMouseConnected(true)' );
    if ( truth_value($touch) ) {
        expect_locator( $summary, 'to_be_visible' );
        assert_ok( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ),
            'not binds.evaluate(\'node => node.open\')' );
        expect_locator( $aim, 'to_be_hidden' );
        Leqra::IntroTour::open_controls_binds($page);
    }
    expect_locator( $aim,  'to_be_visible' );
    expect_locator( $fire, 'to_be_visible' );
    evaluate_js( $page, 'setTestMouseConnected(false)' );
    expect_locator( $aim,  'to_be_hidden' );
    expect_locator( $fire, 'to_be_hidden' );
    if ( truth_value($touch) ) {
        expect_locator( $binds, 'to_be_hidden' );
        $page->keyboard()->press('Shift');
        expect_locator( $binds, 'to_be_hidden' );
    }
    else {
        expect_locator( $key_binding, 'to_be_visible' );
    }
    evaluate_js( $page, 'setTestMouseConnected(true)' );
    if ( truth_value($touch) ) {
        Leqra::IntroTour::open_controls_binds($page);
    }
    for $control ( @{ [ $key_binding, $keyboard_help, $reset_keys ] } ) {
        expect_locator( $control, 'to_be_visible' );
    }
    expect_locator( $aim,  'to_be_visible' );
    expect_locator( $fire, 'to_be_visible' );
    $geometry = evaluate_js(
        $page, '() => {
            const rect=node=>{const r=node.getBoundingClientRect();return {width:r.width,height:r.height,right:r.right};};
            return {key:rect(document.querySelector(\'[data-bind="0:fireAlt"]\')),
                toggles:[\'p1MouseAimEnabled\',\'p1MouseFireEnabled\'].map(id=>rect(document.getElementById(id)))};
        }'
    );
    assert_ok(
        !scalar(
            grep {
                my $item = $_;
                !(
                    (
                        do {
                            my $boolean_value =
                              ( ( abs( ( $item->{'width'} - $geometry->{'key'}->{'width'} ) ) <= 1 ) );
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value =
                                  ( ( abs( ( $item->{'height'} - $geometry->{'key'}->{'height'} ) ) <= 1 ) );
                                truth_value($boolean_value)
                                  ? ( ( abs( ( $item->{'right'} - $geometry->{'key'}->{'right'} ) ) <= 1 ) )
                                  : $boolean_value;
                              }
                              : $boolean_value;
                        }
                    )
                )
            } @{ $geometry->{'toggles'} }
        ),
        $geometry
    );
    $caption = sub {
        my ($node) = @_;
        return evaluate_js( $node,
'input=>{const state=input.nextElementSibling,r=state.getBoundingClientRect(),s=getComputedStyle(state),cols=s.gridTemplateColumns.split(\' \').map(parseFloat),gap=parseFloat(s.columnGap),left=r.left+(r.width-cols.reduce((a,b)=>a+b,0)-gap)/2;return {display:s.display,cols,icon:left,text:left+cols[0]+gap,content:getComputedStyle(state,\'::after\').content};}'
        );
    };
    $on = $caption->($aim);
    assert_ok(
        (
            do {
                my $boolean_value = ( value_eq( $on->{'display'}, 'grid' ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( scalar( @{ $on->{'cols'} } ), 2 ) );
                    truth_value($boolean_value)
                      ? ( ( abs( ( $on->{'cols'}->[0] - 16 ) ) < 0.1 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        $on
    );
    expect_locator( $aim,  'to_have_attribute', 'type', 'checkbox' );
    expect_locator( $fire, 'to_have_attribute', 'type', 'checkbox' );
    expect_locator( $aim,  'to_be_checked' );
    expect_locator( $fire, 'to_be_checked' );
    $aim->press('Space');
    expect_locator( $aim,  'not_to_be_checked' );
    expect_locator( $aim,  'to_be_focused' );
    expect_locator( $fire, 'to_be_checked' );
    $off = $caption->($aim);
    assert_ok(
        (
            do {
                my $boolean_value =
                  ( value_eq( $on->{'cols'}, $off->{'cols'} ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( ( abs( ( $on->{'icon'} - $off->{'icon'} ) ) < 0.1 ) );
                    truth_value($boolean_value)
                      ? ( ( abs( ( $on->{'text'} - $off->{'text'} ) ) < 0.1 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        [ $on, $off ]
    );
    assert_ok(
        (
            do {
                my $boolean_value =
                  ( contains_value( $on->{'content'}, 'ON' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $off->{'content'}, 'OFF' ) )
                  : $boolean_value;
            }
        ),
        [ $on, $off ]
    );
    $box = $aim->boundingBox();
    $aim->click(
        {
            position => {
                'x' => ( $box->{'width'} - 3 ),
                'y' => ( $box->{'height'} / 2 )
            }
        }
    );
    expect_locator( $aim, 'to_be_checked' );
    $fire->press('Space');
    expect_locator( $fire, 'not_to_be_checked' );
    expect_locator( $fire, 'to_be_focused' );
    expect_locator( $aim,  'to_be_checked' );
    $aim->press('Space');
    expect_locator( $aim, 'not_to_be_checked' );
    $box = $fire->boundingBox();
    $fire->click(
        {
            position => {
                'x' => ( $box->{'width'} - 3 ),
                'y' => ( $box->{'height'} / 2 )
            }
        }
    );
    expect_locator( $fire, 'to_be_checked' );
    expect_locator( $aim,  'not_to_be_checked' );
    $off_caption = $caption->($aim);
    $on_caption  = $caption->($fire);
    assert_ok(
        (
            do {
                my $boolean_value = ( ( abs( ( $off_caption->{'icon'} - $on_caption->{'icon'} ) ) < 0.1 ) );
                truth_value($boolean_value)
                  ? ( ( abs( ( $off_caption->{'text'} - $on_caption->{'text'} ) ) < 0.1 ) )
                  : $boolean_value;
            }
        ),
        [ $off_caption, $on_caption ]
    );
    $stored = evaluate_js( $page, 'JSON.parse(localStorage.getItem(\'leqra.feedback.v1\'))' );
    assert_ok(
        (
            do {
                my $boolean_value =
                  ( value_eq( $stored->{'mouseAim'}, JSON::PP::false ) );
                truth_value($boolean_value)
                  ? ( value_eq( $stored->{'mouseFire'}, JSON::PP::true ) )
                  : $boolean_value;
            }
        ),
        $stored
    );
    $page->locator('[data-close-dialog="controlsDialog"]')->click();
    Leqra::IntroTour::open_room_controls($page);
    assert_ok( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ),
        'not binds.evaluate(\'node => node.open\')' );
    $page->reload();
    wait_js( $page, '() => !!window.leqraInfinity' );
    evaluate_js( $page, 'setTestMouseConnected(true)' );
    Leqra::IntroTour::open_room_controls($page);
    assert_ok( ( !truth_value( evaluate_js( $binds, 'node => node.open' ) ) ),
        'not binds.evaluate(\'node => node.open\')' );
    Leqra::IntroTour::open_controls_binds($page);
    expect_locator( $key_binding,                          'to_be_visible' );
    expect_locator( $page->locator('#p1MouseAimEnabled'),  'not_to_be_checked' );
    expect_locator( $page->locator('#p1MouseFireEnabled'), 'to_be_checked' );
    assert_ok(
        ( value_eq( $page->locator('#controlsKeyboardHelp')->innerText()->count($tip_text), 1 ) ),
        'page.locator(\'#controlsKeyboardHelp\').inner_text().count(tip_text)==1'
    );
    expect_locator( $page->locator('#controlsKeyboardHelp .controls-shortcuts kbd'),
        'to_have_text', [ 'P', 'ESC', 'M', 'F' ] );
    expect_locator( $page->locator('#controlsKeyboardHelp .controls-shortcuts .control-keycaps')->first(),
        'to_have_text', 'P/ESC' );
    expect_locator( $page->locator('#controlsKeyboardHelp .controls-firing-help'),
        'to_have_text', ( $tip_text . ' With one local tank, both keyboard layouts control it.' ) );
    assert_ok(
        evaluate_js(
            $page->locator('#controlsKeyboardHelp'),
'node=>node.querySelector(\'.controls-firing-help\').getBoundingClientRect().top>=node.querySelector(\'.controls-shortcuts\').getBoundingClientRect().bottom'
        ),
'page.locator(\'#controlsKeyboardHelp\').evaluate("node=>node.querySelector(\'.controls-firing-help\').getBoundingClientRect().top>=node.querySelector(\'.controls-shortcuts\').getBoundingClientRect().bottom")'
    );

    if ( truth_value($screenshot_dir) ) {
        $page->screenshot(
            {
                path => format_value(
                    $screenshot_dir->child(
                        ( $browser->browserType()->name() . '-' . $width . '-mouse-checkboxes.png' )
                    )
                )
            }
        );
    }
    $page->locator('#openIntroTour')->click();
    if ( truth_value($touch) ) {
        Leqra::IntroTour::check_touch_tour($page);
    }
    else {
        Leqra::IntroTour::check_desktop_tour( $page, JSON::PP::false );
    }
    Leqra::IntroTour::advance_drive_practice( $page, $touch );
    Leqra::IntroTour::check_fire_tour( $page, $touch );
    if ( truth_value($touch) ) {
        $tip = $page->locator('#introTourTouchFire')->getByText(
'Drag the center of Fire to aim without shooting. Tap the center to shoot on release, or hold the outer area for continuous fire.',
            { exact => JSON::PP::true }
        );
    }
    else {
        $tip = $page->locator('#introTourKeyboardFire .intro-fire-tip');
        expect_locator( $tip, 'to_have_text', $tip_text );
    }
    evaluate_js( $page->locator('#introTourDialog'), 'node => node.scrollTop=node.scrollHeight' );
    expect_locator( $tip, 'to_be_in_viewport', { ratio => 1 } );
    $next_button = $page->locator('#introTourNext');
    expect_locator( $next_button, 'to_be_in_viewport', { ratio => 1 } );
    assert_ok(
        evaluate_js(
            $next_button,
'node=>{const r=node.getBoundingClientRect();return r.height>=44&&node.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));}'
        ),
'next_button.evaluate("""node=>{const r=node.getBoundingClientRect();return r.height>=44&&node.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));}""")'
    );
    assert_ok(
        evaluate_js( $page->locator('#introTourDialog'), 'node => node.scrollWidth <= node.clientWidth' ),
        'page.locator(\'#introTourDialog\').evaluate(\'node => node.scrollWidth <= node.clientWidth\')'
    );
    if ( truth_value($screenshot_dir) ) {
        $page->screenshot(
            {
                path => format_value(
                    $screenshot_dir->child(
                        ( $browser->browserType()->name() . '-' . $width . '-tour-fire-tip.png' )
                    )
                )
            }
        );
    }
    Leqra::IntroTour::advance_fire_practice( $page, $touch, undef, ( !truth_value($touch) ) );
    $page->locator('#introTourSkip')->click();
    $page->locator('[data-close-dialog="controlsDialog"]')->click();
    for $paired ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
        evaluate_js(
            $page,
'paired=>leqraInfinity.start(\'offline\',{name:\'ONE\',...(paired?{localName:\'TWO\'}:{}),roomRules:{infinityRandomBots:false}})',
            $paired
        );
        $page->locator('#pauseBtn')->click();
        $manual = $page->locator('#infinitePauseSidebar #manualContent');
        expect_locator( $manual->locator('.manual-controls .control-player'),
            'to_have_count', ( truth_value($paired) ? 2 : 1 ) );
        $shared = $manual->locator('.manual-shared-controls');
        if ( truth_value( ( !truth_value($paired) ) ) ) {
            $solo_tip = $manual->locator('.manual-controls > .manual-fire-tip');
            expect_locator( $solo_tip,                            'to_have_text',  $tip_text );
            expect_locator( $shared->locator('.manual-fire-tip'), 'to_have_count', 0 );
            assert_ok(
                evaluate_js(
                    $solo_tip,
'tip=>tip.getBoundingClientRect().top>=tip.previousElementSibling.getBoundingClientRect().bottom'
                ),
'solo_tip.evaluate("tip=>tip.getBoundingClientRect().top>=tip.previousElementSibling.getBoundingClientRect().bottom")'
            );
            $page->locator('#infiniteExit')->click();
            next;
        }
        $shared_tip = $shared->locator(':scope > .manual-fire-tip');
        expect_locator( $shared_tip,                                           'to_have_text',  $tip_text );
        expect_locator( $manual->locator('.manual-controls .manual-fire-tip'), 'to_have_count', 0 );
        $manual->scrollIntoViewIfNeeded();
        $data = evaluate_js( $shared_tip,
'tip=>{const shared=tip.parentElement,controls=shared.previousElementSibling,rows=[...controls.querySelectorAll(\'.control-player\')],r=tip.getBoundingClientRect(),s=getComputedStyle(shared);return {outside:!tip.closest(\'.control-player\'),after:r.top>=Math.max(...rows.map(row=>row.getBoundingClientRect().bottom)),border:parseFloat(s.borderTopWidth),borderStyle:s.borderTopStyle,neutral:!rows.map(row=>getComputedStyle(row.querySelector(\'.control-pilot\')).color).includes(getComputedStyle(tip).color),first:shared.firstElementChild===tip,noNames:!tip.querySelector(\'.pilot-identity,.control-pilot\')};}'
        );
        assert_ok(
            (
                do {
                    my $boolean_value = $data->{'outside'};
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = $data->{'after'};
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value = ( ( $data->{'border'} >= 1 ) );
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value = ( !value_eq( $data->{'borderStyle'}, 'none' ) );
                                truth_value($boolean_value)
                                  ? do {
                                    my $boolean_value = $data->{'neutral'};
                                    truth_value($boolean_value)
                                      ? do {
                                        my $boolean_value = $data->{'first'};
                                        truth_value($boolean_value)
                                          ? $data->{'noNames'}
                                          : $boolean_value;
                                      }
                                      : $boolean_value;
                                  }
                                  : $boolean_value;
                              }
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            $data
        );
        if (
            truth_value(
                (
                    do {
                        my $boolean_value = $screenshot_dir;
                        truth_value($boolean_value) ? $paired : $boolean_value;
                    }
                )
            )
          )
        {
            $page->screenshot(
                {
                    path => format_value(
                        $screenshot_dir->child(
                            ( $browser->browserType()->name() . '-' . $width . '-shared-fire-tip.png' )
                        )
                    )
                }
            );
        }
        $page->locator('#infiniteExit')->click();
    }
    assert_ok( ( !truth_value($errors) ), $errors );
    print(
        join(
            " ",
            (
                    'PASS '
                  . $browser->browserType()->name() . ' '
                  . $width
                  . ': native full-width mouse checkboxes, independent saved states, accessible tour Next, shared neutral fire tip for one/two pilots'
            )
        ),
        "\n"
    );
    $context->close();
}

sub check_context {
    my ( $browser, $url, $width, $height, $touch, $screenshot_dir ) = @_;
    my (
        $choose_step,  $context,       $dots,         $errors,    $github,    $header_shot,
        $key,          $keyboard_help, $maze_tips,    $page,      $room_name, $screenshot,
        $sidebar_note, $toggle,        $tour_details, $tour_kind, $unicode_room
    );
    $screenshot_dir //= undef;
    $context = $browser->newContext(
        {
            viewport       => { 'width' => $width, 'height' => $height },
            isMobile       => $touch,
            hasTouch       => $touch,
            serviceWorkers => 'block'
        }
    );
    $page   = $context->newPage();
    $errors = [];
    capture_event( $page, 'pageerror', $errors, '(error) => String(error)' );
    if ( truth_value($touch) ) {
        Leqra::IntroTour::emulate_controls_device( $page, JSON::PP::true );
    }
    $page->goto($url);
    expect_locator( $page->locator('#introTourDialog'), 'to_be_visible' );
    if ( truth_value($touch) ) {
        Leqra::IntroTour::check_touch_tour($page);
    }
    else {
        Leqra::IntroTour::check_desktop_tour($page);
        $keyboard_help = $page->locator('#introTourKeyboard');
        Leqra::IntroTour::check_control_rows( $keyboard_help, ['Movement'] );
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourMoveKeys'),
            [ 'W', 'A', 'S', 'D', '↑', '←', '↓', '→' ] );
        Leqra::IntroTour::check_mouse_symbols($page);
    }
    expect_locator( $page->locator('#introTourBack'), 'to_be_disabled' );
    Leqra::IntroTour::check_buttons( $page, 'Next' );
    Leqra::IntroTour::advance_drive_practice( $page, $touch );
    Leqra::IntroTour::check_fire_tour( $page, $touch );
    if ( truth_value( ( !truth_value($touch) ) ) ) {
        Leqra::IntroTour::check_keycaps( $page->locator('#introTourFireKeys'),
            [ 'Q', 'C', 'SPACE', 'ENTER' ] );
    }
    Leqra::IntroTour::check_buttons( $page, 'Next' );
    Leqra::IntroTour::advance_fire_practice( $page, $touch );
    $page->locator('#introTourBack')->click();
    expect_locator( $page->locator('#introTourTitle'), 'to_have_text', 'Fire' );
    expect_locator( $page->locator('#introTourNext'), 'to_be_enabled' );
    $page->locator('#introTourNext')->click();
    Leqra::IntroTour::check_buttons( $page, 'Next' );
    Leqra::IntroTour::advance_score_practice( $page, $touch );
    $choose_step = $page->locator('[data-intro-page="3"]');
    expect_locator( $choose_step->locator(':scope > ul li > strong'),
        'to_have_text',
        [ 'Public Infinity', 'Elimination', 'Capture the Flag', 'King of the Hill', 'Survival' ] );
    $maze_tips = $choose_step->locator('#introTourMazeTips');
    expect_locator( $maze_tips->locator('li > strong'), 'to_have_text', [ 'Laser', 'Grenade', 'Starman' ] );
    $sidebar_note = $maze_tips->getByText('Check the sidebar for the full list of power-ups.');
    expect_locator( $sidebar_note, 'to_be_hidden' );
    $maze_tips->locator('summary')->click();
    expect_locator( $sidebar_note, 'to_be_visible' );

    if ( truth_value($touch) ) {
        $sidebar_note->scrollIntoViewIfNeeded();
        expect_locator( $sidebar_note, 'to_be_in_viewport', { ratio => 1 } );
    }
    Leqra::IntroTour::check_buttons( $page, 'Done' );
    $page->locator('#introTourNext')->click();
    expect_locator( $page->locator('#introTourDialog'), 'to_be_hidden' );
    $github = $page->locator('.github-link');
    expect_locator( $github, 'to_be_visible' );
    expect_locator( $github, 'to_have_attribute', 'href', 'https://github.com/nhooyr/leqra' );
    assert_ok(
        evaluate_js( $page, 'document.documentElement.scrollWidth === innerWidth' ),
        'page.evaluate("document.documentElement.scrollWidth === innerWidth")'
    );

    if (
        truth_value(
            (
                do {
                    my $boolean_value =
                      ( contains_value( [ 320, 390 ], $width ) );
                    truth_value($boolean_value)
                      ? ( contains_value( [ 'http', 'https' ], URI->new($url)->scheme() ) )
                      : $boolean_value;
                }
            )
        )
      )
    {
        Leqra::IntroTour::check_public_headers( $page, JSON::PP::false );
    }
    $toggle = $page->locator('#infinityToggle');
    if (
        truth_value(
            (
                do {
                    my $boolean_value = $toggle->isEnabled();
                    truth_value($boolean_value)
                      ? $toggle->isChecked()
                      : $boolean_value;
                }
            )
        )
      )
    {
        $toggle->uncheck();
    }
    $tour_kind  = ( truth_value($touch) ? 'touch' : 'keycaps' );
    $screenshot = (
        truth_value($screenshot_dir)
        ? $screenshot_dir->child(
            ( $browser->browserType()->name() . '-' . $width . '-tour-' . $tour_kind . '.png' )
          )
        : undef
    );
    Leqra::IntroTour::check_remapped_tour( $page, $touch, $screenshot );
    if (
        truth_value(
            (
                do {
                    my $boolean_value =
                      ( contains_value( [ 320, 390 ], $width ) );
                    truth_value($boolean_value)
                      ? ( contains_value( [ 'http', 'https' ], URI->new($url)->scheme() ) )
                      : $boolean_value;
                }
            )
        )
      )
    {
        $header_shot = (
            truth_value($screenshot_dir)
            ? $screenshot_dir->child(
                ( $browser->browserType()->name() . '-' . $width . '-public-p2-header.png' )
              )
            : undef
        );
        Leqra::IntroTour::check_public_headers( $page, JSON::PP::true, $header_shot );
    }
    if ( truth_value( ( ( $width <= 920 ) ) ) ) {
        if ( truth_value( ( !truth_value($touch) ) ) ) {
            $page->locator('#startRoomBtn')->click();
            wait_js( $page, '() => leqra.getState().phase === \'playing\'' );
        }
        if ( truth_value( ( value_eq( $width, 320 ) ) ) ) {
            evaluate_js(
                $page, '() => {
                    __test.setLocalRules({...__test.currentRules(), teamMode:\'ffa\'});
                    for (let count = __test.localRoom.players.length; count < 8; count++) {
                        __test.addRoomSeat(\'bot\');
                    }
                }'
            );
            $dots = $page->locator('#miniScores .mini-score i');
            expect_locator( $dots, 'to_have_count', 8 );
            assert_ok(
                !scalar(
                    grep { my $width = $_; !( ( ( $width >= 4 ) ) ) } @{
                        inspect_elements(
                            $page,
                            '#miniScores .mini-score i',
                            'dots => dots.map(dot => dot.getBoundingClientRect().width)'
                        )
                    }
                ),
                'all(width >= 4 for width in dots.evaluate_all(
                    "dots => dots.map(dot => dot.getBoundingClientRect().width)"
                ))'
            );
        }
        Leqra::IntroTour::check_sidebar( $page, $touch );
    }
    if ( truth_value( ( value_eq( $width, 1280 ) ) ) ) {
        expect_locator( $page->locator('#sidebarDetailsBtn'), 'to_be_hidden' );
        expect_locator( $page->locator('#gameSidebar'),       'to_be_visible' );
        $page->locator('#roomSettings > summary')->click();
        $room_name = $page->locator('#localRoomName');
        $room_name->fill('');
        $room_name->focus();
        $unicode_room = ( '🎮' x 128 );
        $page->keyboard()->insertText($unicode_room);
        expect_locator( $room_name, 'to_have_value', $unicode_room );
        $page->locator('#startRoomBtn')->click();
        wait_js( $page, '() => leqra.getState().phase === \'playing\'' );
        evaluate_js(
            $github, 'link => link.addEventListener(\'click\', event => {
                event.preventDefault();
                link.dataset.activated = \'true\';
            })'
        );
        $github->press('Enter');
        expect_locator( $github, 'to_have_attribute', 'data-activated', 'true' );

        for $key ( @{ [ 'Space', 'Enter' ] } ) {
            $page->locator('#pauseBtn')->press($key);
            expect_locator( $page->locator('#onlineMenuScreen'), 'to_be_visible' );
            $page->locator('#onlineReturnBtn')->press($key);
            expect_locator( $page->locator('#onlineMenuScreen'), 'to_be_hidden' );
        }
    }
    assert_ok( ( !truth_value($errors) ), $errors );
    $tour_details = (
        truth_value($touch)
        ? 'touch-only Quick Tour practice for solo and paired play'
        : 'keyboard and mouse Quick Tour practice with remapped controls'
    );
    print(
        join(
            " ",
            (
                    'PASS '
                  . $browser->browserType()->name() . ' '
                  . $width . 'x'
                  . $height . ': '
                  . $tour_details
            )
        ),
        "\n"
    );
    $context->close();
}

sub check_mobile_device_identity {
    my ( $browser, $url ) = @_;
    my ( $context, $label, $page, $profiles, $setup, $user_agent );
    $profiles = [
        [ 'Android tablet', 'Mozilla/5.0 (Linux; Android 15; Tablet)', '' ],
        [
            'iPad desktop site',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', '
            Object.defineProperty(navigator, \'platform\', {value: \'MacIntel\'});
            Object.defineProperty(navigator, \'maxTouchPoints\', {value: 5});
        '
        ]
    ];
    for my $item ( @{$profiles} ) {
        my $tuple_706_8 = $item;
        my $label       = $tuple_706_8->[0];
        my $user_agent  = $tuple_706_8->[1];
        my $setup       = $tuple_706_8->[2];
        my $context     = $browser->newContext(
            {
                viewport       => { 'width' => 1200, 'height' => 800 },
                userAgent      => $user_agent,
                serviceWorkers => 'block'
            }
        );
        my $page = $context->newPage();
        if ( truth_value($setup) ) {
            $page->addInitScript($setup);
        }
        $page->goto($url);
        assert_ok( ( !truth_value( evaluate_js( $page, 'matchMedia(\'(pointer: coarse)\').matches' ) ) ),
            'not page.evaluate("matchMedia(\'(pointer: coarse)\').matches")' );
        expect_locator( $page->locator('#introTourDialog'), 'to_be_visible' );
        Leqra::IntroTour::check_touch_tour($page);
        $context->close();
        print(
            join(
                " ",
                (
                        'PASS '
                      . $browser->browserType()->name() . ': '
                      . $label
                      . ' gets a touch-only Quick Tour with a fine pointer'
                )
            ),
            "\n"
        );
    }
}

sub check_desktop_touchscreen_tour {
    my ( $browser, $url ) = @_;
    my ( $context, $page, $toggle );
    $context = $browser->newContext(
        {
            viewport       => { 'width' => 620, 'height' => 900 },
            serviceWorkers => 'block'
        }
    );
    $page = $context->newPage();
    $page->addInitScript( '
            Object.defineProperty(navigator, \'platform\', {value: \'Win32\'});
            Object.defineProperty(navigator, \'maxTouchPoints\', {value: 5});
        ' );
    $page->goto($url);
    assert_ok(
        evaluate_js( $page, 'matchMedia(\'(pointer: fine)\').matches' ),
        'page.evaluate("matchMedia(\'(pointer: fine)\').matches")'
    );
    expect_locator( $page->locator('#introTourDialog'), 'to_be_visible' );
    Leqra::IntroTour::check_desktop_tour($page);
    $page->locator('#introTourSkip')->click();
    $toggle = $page->locator('#infinityToggle');
    if (
        truth_value(
            (
                do {
                    my $boolean_value = $toggle->isEnabled();
                    truth_value($boolean_value)
                      ? $toggle->isChecked()
                      : $boolean_value;
                }
            )
        )
      )
    {
        $toggle->uncheck();
    }
    $page->locator('#roomPlayers > summary')->click();
    $page->locator('#addLocalBtn')->click();
    Leqra::IntroTour::open_room_controls($page);
    $page->locator('#openIntroTour')->click();
    Leqra::IntroTour::check_desktop_tour($page);
    $context->close();
    print(
        join(
            " ",
            (
                    'PASS '
                  . $browser->browserType()->name()
                  . ': narrow touchscreen desktop Quick Tour shows only hardware controls'
            )
        ),
        "\n"
    );
}
unless (caller) {
    $parser = {};
    $args   = do {
        my %args = ( 'url' => undef, 'browser' => [], 'screenshots' => undef );
        my $help;
        GetOptions(
            'browser=s@'    => $args{'browser'},
            'screenshots=s' => \$args{'screenshots'},
            'help|h'        => \$help
          )
          or die 'Usage: perl intro_tour_browser.pl url --browser --screenshots
';
        if ($help) {
            print 'Usage: perl intro_tour_browser.pl url --browser --screenshots
';
            exit 0;
        }
        $args{'url'} = shift @ARGV if @ARGV;
        for my $choice ( @{ $args{'browser'} // [] } ) {
            die 'invalid browser
' unless grep { value_eq( $_, $choice ) } @{ [ 'chromium', 'webkit' ] };
        }
        $args{'screenshots'} = path( $args{'screenshots'} )
          if defined( $args{'screenshots'} );
        \%args;
    };
    if ( truth_value( $args->{'screenshots'} ) ) {
        $args->{'screenshots'}->mkpath;
    }
    $target = (
        do {
            my $boolean_value = $args->{'url'};
            truth_value($boolean_value)
              ? $boolean_value
              : URI::file->new_abs( "" . path($0)->absolute->parent(2)->child('web/index.html') )->as_string;
        }
    );
    $parts           = URI->new($target);
    $query           = { map { @$_ } @{ query_pairs( $parts->query ) } };
    $query->{'test'} = '1';
    $target          = url_parts(
        [ $parts->scheme(), $parts->authority(), $parts->path(), query_string($query), $parts->fragment() ] );
    $playwright = start_playwright();
    for $engine (
        @{
            (
                do {
                    my $boolean_value = $args->{'browser'};
                    truth_value($boolean_value)
                      ? $boolean_value
                      : [ 'chromium', 'webkit' ];
                }
            )
        }
      )
    {
        $browser = $playwright->launch(
            type => ( $engine eq "chromium" ? "chrome" : $engine ),
            %{
                (
                    truth_value( ( value_eq( $engine, 'chromium' ) ) )
                    ? { 'chromiumSandbox' => JSON::PP::true }
                    : {}
                )
            }
        );
        eval {
            for my $item (
                @{
                    [
                        [ 1280, 900, JSON::PP::false ],
                        [ 320,  568, JSON::PP::true ],
                        [ 390,  844, JSON::PP::true ],
                        [ 844,  390, JSON::PP::true ]
                    ]
                }
              )
            {
                my $tuple_757_20 = $item;
                my $width        = $tuple_757_20->[0];
                my $height       = $tuple_757_20->[1];
                my $touch        = $tuple_757_20->[2];
                Leqra::IntroTour::check_context( $browser, $target, $width,
                    $height, $touch, $args->{'screenshots'} );
            }
            Leqra::IntroTour::check_mobile_device_identity( $browser, $target );
            Leqra::IntroTour::check_desktop_touchscreen_tour( $browser, $target );
            Leqra::IntroTour::check_mobile_controls_hardware( $browser, $target );
            for my $item (
                @{
                    [
                        [ 1280, 900, JSON::PP::false ],
                        [ 500,  800, JSON::PP::true ],
                        [ 320,  568, JSON::PP::true ],
                        [ 390,  844, JSON::PP::true ],
                        [ 844,  390, JSON::PP::true ]
                    ]
                }
              )
            {
                my $tuple_762_20 = $item;
                my $width        = $tuple_762_20->[0];
                my $height       = $tuple_762_20->[1];
                my $touch        = $tuple_762_20->[2];
                Leqra::IntroTour::check_mouse_preferences( $browser, $target,
                    $width, $height, $touch, $args->{'screenshots'} );
            }
            1;
        };
        my $caught_error = $@;
        $browser->close();
        die $caught_error if $caught_error;
    }
}
