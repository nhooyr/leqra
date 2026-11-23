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

my ( $args, $browser, $engine, $height, $parser, $playwright, $touch, $width );

# Check the 10px UI font floor and wrapping in Chromium and WebKit.
#
# Run with Playwright installed: perl src/tests/typography_browser.pl [server URL]
# Without a URL this checks the current source directly, including offline Infinity.
require "$FindBin::Bin/intro_tour_browser.pl";

sub check_text {
    my ($page) = @_;
    my ( $dialog, $names, $small );
    $small = evaluate_js(
        $page, '() => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), bad = [];
        for (let node; node = walker.nextNode();) {
            if (!node.textContent.trim()) continue;
            const parent = node.parentElement;
            if (!parent || !parent.getClientRects().length) continue;
            const style = getComputedStyle(parent);
            if (style.visibility === \'hidden\' || style.display === \'none\') continue;
            const size = parseFloat(style.fontSize);
            if (size < 9.99) bad.push({text: node.textContent.slice(0, 60), size, id: parent.id});
        }
        return bad;
    }'
    );
    assert_ok( ( !truth_value($small) ), $small );
    assert_ok( evaluate_js( $page, 'document.documentElement.scrollWidth <= innerWidth' ),
        'Horizontal page overflow' );
    for $dialog ( @{ $page->locator('dialog[open]')->all() } ) {
        assert_ok( evaluate_js( $dialog, 'node => node.scrollWidth <= node.clientWidth' ),
            $dialog->getAttribute('id') );
    }
    $names = $page->locator('.loadout-name:visible, .control-pilot:visible');
    assert_ok(
        inspect_elements(
            $page,
            '.loadout-name:visible, .control-pilot:visible',
'nodes => nodes.every(node => node.scrollWidth <= node.clientWidth && node.scrollHeight <= node.clientHeight)'
        ),
        $names->allTextContents()
    );
}

sub check_context {
    my ( $browser, $url, $width, $height, $touch ) = @_;
    my ( $context, $errors, $page, $paired, $toggle );
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
    $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\', \'1\')');
    $page->goto($url);
    wait_js( $page, '() => !!window.leqraInfinity' );
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
    for $paired ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
        if ( truth_value($paired) ) {
            evaluate_js( $page->locator('#roomPlayers'), 'node => node.open = true' );
            $page->locator('#addLocalBtn')->click();
        }
        main::check_text($page);
        $page->locator('#roomControlsBtn')->click();
        main::check_text($page);
        $page->locator('#showFPS')->check();
        $page->locator('[data-close-dialog="controlsDialog"]')->click();
        evaluate_js( $page->locator('#roomSettings'), 'node => node.open = true' );
        $page->locator('[data-room-mode="elimination"]')->click();
        $page->locator('#roomRulesBtn')->click();
        main::check_text($page);
        $page->locator('[data-close-dialog="rulesDialog"]')->click();
        $page->locator('#startRoomBtn')->click();
        wait_js( $page, '() => leqra.getState().phase === \'playing\'' );
        main::check_text($page);
        $page->locator('#pauseBtn')->click();
        expect_locator( $page->locator('#onlineMenuScreen'), 'to_be_visible' );
        main::check_text($page);
        $page->locator('#returnRoomBtn')->click();
        evaluate_js( $page->locator('#roomSettings'), 'node => node.open = true' );
        $page->locator('[data-room-mode="infinity"]')->click();
        $page->locator('#startRoomBtn')->click();
        expect_locator( $page->locator('#infiniteArena'), 'to_be_visible' );
        main::check_text($page);
        $page->locator('#pauseBtn')->click();
        main::check_text($page);
        $page->locator('#infiniteControlsBtn')->click();
        main::check_text($page);
        $page->locator('#openIntroTour')->click();
        main::check_text($page);
        Leqra::IntroTour::advance_drive_practice( $page, $touch );
        main::check_text($page);
        Leqra::IntroTour::advance_fire_practice( $page, $touch );
        main::check_text($page);
        Leqra::IntroTour::advance_score_practice( $page, $touch );
        main::check_text($page);
        $page->locator('#introTourNext')->click();
        $page->locator('[data-close-dialog="controlsDialog"]')->click();
        $page->locator('#infiniteExit')->click();
        print(
            join(
                " ",
                (
                        'PASS '
                      . $browser->browserType()->name() . ' '
                      . $width . 'x'
                      . $height . ' '
                      . ( truth_value($paired) ? 'two pilots' : 'solo' )
                      . ': font floor, controls, rules, fixed/Infinity HUD, pause and tour'
                )
            ),
            "\n"
        );
    }
    assert_ok( ( !truth_value($errors) ), $errors );
    $context->close();
}
unless (caller) {
    $parser = {};
    $args   = do {
        my %args = (
            'url' => (
                URI::file->new_abs( "" . path($0)->absolute->parent(2)->child('web/index.html') )->as_string
                  . '?test=1'
            ),
            'browser' => []
        );
        my $help;
        GetOptions( 'browser=s@' => $args{'browser'}, 'help|h' => \$help )
          or die 'Usage: perl typography_browser.pl url --browser
';
        if ($help) {
            print 'Usage: perl typography_browser.pl url --browser
';
            exit 0;
        }
        $args{'url'} = shift @ARGV if @ARGV;
        for my $choice ( @{ $args{'browser'} // [] } ) {
            die 'invalid browser
' unless grep { value_eq( $_, $choice ) } @{ [ 'chromium', 'webkit' ] };
        }
        \%args;
    };
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
        $browser = $playwright->launch( type => ( $engine eq "chromium" ? "chrome" : $engine ) );
        eval {
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
                my $tuple_100_20 = $item;
                my $width        = $tuple_100_20->[0];
                my $height       = $tuple_100_20->[1];
                my $touch        = $tuple_100_20->[2];
                main::check_context( $browser, $args->{'url'}, $width, $height, $touch );
            }
            1;
        };
        my $caught_error = $@;
        $browser->close();
        die $caught_error if $caught_error;
    }
}
