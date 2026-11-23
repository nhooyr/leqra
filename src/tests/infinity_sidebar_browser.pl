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

my ( $args, $browser, $mobile, $parser, $playwright );

# Check Infinity Combat Log visibility against a dedicated leqra server.
#
# perl src/tests/infinity_sidebar_browser.pl http://localhost:8080
sub check_sidebar {
    my ( $browser, $url, $mobile, $source_css ) = @_;
    my ( $asset, $context, $errors, $expect_log, $index, $log, $mode, $page, $selected );
    $context = $browser->newContext(
        {
            viewport => {
                'width'  => ( truth_value($mobile) ? 390 : 1280 ),
                'height' => 844
            },
            hasTouch       => $mobile,
            isMobile       => $mobile,
            serviceWorkers => 'block'
        }
    );
    if ( truth_value($source_css) ) {
        $index =
          path($0)->absolute->parent(2)->child('web')->child('index.html');
        $asset = match_re( 'href="(assets/v[^/"]+/style.css)"', $index->slurp_utf8 )->[1];
        fixture_response( $context, $url, $asset, $index->parent->child($asset)->slurp_utf8, 'text/css' );
    }
    $page   = $context->newPage();
    $errors = [];
    capture_event( $page, 'pageerror', $errors, '(error) => String(error)' );
    $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\', \'1\')');
    $page->goto( ( trim_text( $url, '/', 'rstrip' ) . '/?test' ) );
    wait_js( $page, '() => !!window.leqraInfinity && !!window.__test' );
    $log = $page->locator('#combatLog');
    evaluate_js( $log, 'element => element.textContent = \'Preserved fixed-maze log\'' );
    $expect_log = sub {
        my ($hidden) = @_;
        expect_locator( $page->locator('.log-panel'),
            'to_have_css', 'display', ( truth_value($hidden) ? 'none' : 'block' ) );
        expect_locator( $log, 'to_have_text', 'Preserved fixed-maze log' );
    };
    expect_locator( $page->locator('body'), 'to_have_class', regex('\\binfinity-preview\\b') );
    $expect_log->(JSON::PP::true);
    evaluate_js( $page->locator('#sidebarDetailsBtn'), 'button => button.click()' );
    expect_locator( $page->locator('#sidebarDialog #gameSidebar'), 'to_be_visible' );
    $expect_log->(JSON::PP::true);
    $page->locator('#sidebarCloseBtn')->click();
    $page->locator('#infinityToggle')->uncheck();
    $expect_log->(JSON::PP::false);

    for $selected ( @{ [ JSON::PP::true, JSON::PP::false ] } ) {
        evaluate_js( $page,
            'selected => __test.setLocalRules({...__test.currentRules(), infinity: selected})', $selected );
        $expect_log->($selected);
    }
    for $mode ( @{ [ 'offline', 'online' ] } ) {
        evaluate_js( $page, 'mode => leqraInfinity.start(mode, {public: mode === \'online\'})', $mode );
        expect_locator( $page->locator('#infiniteArena'), 'to_be_visible' );
        $expect_log->(JSON::PP::true);
        $page->locator( ( truth_value($mobile) ? '#pauseBtn' : '#sidebarBtn' ) )->click();
        expect_locator( $page->locator('#infinitePauseSidebar #gameSidebar'), 'to_be_visible' );
        $expect_log->(JSON::PP::true);
        $page->locator('#infiniteResumeBtn')->click();
        $expect_log->(JSON::PP::true);
        evaluate_js( $page, '() => leqraInfinity.close()' );
        $expect_log->(JSON::PP::false);
    }
    assert_ok( ( !truth_value($errors) ), $errors );
    $context->close();
    print(
        join(
            " ",
            (
                    'PASS '
                  . ( truth_value($mobile) ? 'mobile' : 'desktop' )
                  . ' Infinity preview, Sidebar dialog, pause, and fixed-maze restoration'
            )
        ),
        "\n"
    );
}
unless (caller) {
    $parser = {};
    $args   = do {
        my %args = (
            'url'        => 'http://localhost:8080',
            'engine'     => 'chromium',
            'source_css' => undef
        );
        my $help;
        GetOptions(
            'engine=s'    => \$args{'engine'},
            'source-css!' => \$args{'source_css'},
            'help|h'      => \$help
          )
          or die 'Usage: perl infinity_sidebar_browser.pl url --engine --source-css
';
        if ($help) {
            print 'Usage: perl infinity_sidebar_browser.pl url --engine --source-css
';
            exit 0;
        }
        $args{'url'} = shift @ARGV if @ARGV;
        die 'invalid engine
'
          if defined( $args{'engine'} )
          && !grep { value_eq( $_, $args{'engine'} ) } @{ [ 'chromium', 'webkit' ] };
        \%args;
    };
    $playwright = start_playwright();
    $browser =
      $playwright->launch( type => ( $args->{'engine'} eq "chromium" ? "chrome" : $args->{'engine'} ) );
    eval {
        for $mobile ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
            main::check_sidebar( $browser, $args->{'url'}, $mobile, $args->{'source_css'} );
        }
        1;
    };
    my $caught_error = $@;
    $browser->close();
    die $caught_error if $caught_error;
}
