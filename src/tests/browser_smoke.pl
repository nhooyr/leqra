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

my (
    $after,   $angle,   $args,     $assets,  $before,  $browser, $cdp,    $checks,
    $code,    $context, $contexts, $current, $cx,      $cy,      $errors, $fb,
    $h,       $html,    $i,        $js,      $layouts, $mobile,  $old,    $oldCount,
    $options, $out,     $page,     $pages,   $parser,  $phone,   $points, $pos,
    $pw,      $report,  $root,     $st,      $t,       $tick,    $w,      $wrapper
);

# Browser checks with four independent clients. Optional tooling:
#   pip install playwright
#   playwright install chromium
#   perl tests/browser_smoke.pl http://localhost:8080
# Use --isolated only with TestBrowserFixture (see TESTING.md).
$parser = {};
$args   = do {
    my %args = (
        'url'      => 'http://localhost:8080',
        'isolated' => undef,
        'browser'  => undef,
        'output'   => 'test-output'
    );
    my $help;
    GetOptions(
        'isolated!' => \$args{'isolated'},
        'browser=s' => \$args{'browser'},
        'output=s'  => \$args{'output'},
        'help|h'    => \$help
      )
      or die 'Usage: perl browser_smoke.pl url --isolated --browser --output
';
    if ($help) {
        print 'Usage: perl browser_smoke.pl url --isolated --browser --output
';
        exit 0;
    }
    $args{'url'} = shift @ARGV if @ARGV;
    \%args;
};
$root   = path($0)->absolute->parent(2)->child('web');
$assets = asset_directory($root);
$out    = path( $args->{'output'} );
$out->mkpath;
$html = $root->child('index.html')->slurp_utf8;
$html = replace_text(
    replace_text(
        replace_text( replace_re( '<link[^>]*>', '', $html ), '<script src="game.js" defer></script>', '' ),
        '<script src="netcode.js" defer></script>', ''
    ),
    '</head>',
    ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' )
);
$js  = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
$pos = rindex( $js, '})()' );
$js  = (
    ( substr( $js, 0, $pos - 0 ) . ( '})(new URL(' . json_text( ( $args->{'url'} . '/?test=1' ) ) . '));' ) )
    . substr( $js, ( $pos + 4 ) ) );
$wrapper =
'window.__sockets=[];const RealSocket=window.WebSocket;window.WebSocket=class extends RealSocket{constructor(...args){super(...args);window.__sockets.push(this)}};';
$checks = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub load {
    my ($page) = @_;
    if ( truth_value( $args->{'isolated'} ) ) {
        $page->setContent($html);
        evaluate_js( $page, ( ( '()=>{' . $wrapper ) . '}' ) );
        $page->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
        $page->addScriptTag( { content => $js } );
    }
    else {
        $page->addInitScript($wrapper);
        $page->goto( ( $args->{'url'} . '/?test=1' ) );
    }
    wait_js( $page, 'window.leqra' );
}

sub state {
    my ($page) = @_;
    return evaluate_js( $page, 'leqra.getState()' );
}
$pw = start_playwright();
my $playwright = $pw;
$options = { 'headless' => JSON::PP::true };
if ( truth_value( $args->{'browser'} ) ) {
    $options->{'executablePath'} = $args->{'browser'};
}
$browser  = $pw->launch( type => 'chrome', %{$options} );
$pages    = [];
$contexts = [];
$errors   = [];
$layouts  = [
    [ 1365, 950, JSON::PP::false ],
    [ 390,  844, JSON::PP::true ],
    [ 320,  568, JSON::PP::true ],
    [ 844,  390, JSON::PP::true ]
];
for my $item ( @{ [ map { [ $_, $layouts->[$_] ] } 0 .. $#{$layouts} ] } ) {
    my $tuple_44_5 = $item;
    my $i          = $tuple_44_5->[0];
    my $tuple_44_7 = $tuple_44_5->[1];
    my $w          = $tuple_44_7->[0];
    my $h          = $tuple_44_7->[1];
    my $mobile     = $tuple_44_7->[2];
    my $context    = $browser->newContext(
        {
            viewport          => { 'width' => $w, 'height' => $h },
            isMobile          => $mobile,
            hasTouch          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 )
        }
    );
    push( @{$contexts}, $context );
    my $page = $context->newPage();
    push( @{$pages}, $page );
    capture_event( $page, 'pageerror', $errors, '(e) => String(e)' );
    main::load($page);
    $page->locator('[data-mode=online]')->click();
    $page->locator('#pilotName')->fill( [ 'HOST', 'PHONE', 'POCKET', 'WIDE' ]->[$i] );
}
$pages->[0]->locator('#createRoomBtn')->click();
wait_js( $pages->[0], 'leqra.getState().online?.connected' );
$code = main::state( $pages->[0] )->{'online'}->{'code'};
for $page ( @{ array_slice( $pages, 1, undef ) } ) {
    $page->locator('#joinCode')->fill($code);
    $page->locator('#joinRoomBtn')->click();
    wait_js( $page, 'leqra.getState().online?.connected' );
}
for my $item ( @{ [ map { [ $_, $pages->[$_] ] } 0 .. $#{$pages} ] } ) {
    my $tuple_53_5 = $item;
    my $i          = $tuple_53_5->[0];
    my $page       = $tuple_53_5->[1];
    wait_js( $page, 'leqra.getState().online.players.length===4' );
    main::check(
        evaluate_js( $page, 'document.documentElement.scrollWidth<=innerWidth' ),
        ( 'No horizontal overflow: ' . $layouts->[$i]->[0] . 'x' . $layouts->[$i]->[1] )
    );
    $page->screenshot(
        {
            path => format_value(
                $out->child( ( 'lobby-' . $layouts->[$i]->[0] . 'x' . $layouts->[$i]->[1] . '.png' ) )
            )
        }
    );
    $page->locator('#readyBtn')->click();
}
$pages->[0]->locator('#startRoomBtn')->click();
for $page ( @{$pages} ) {
    wait_js( $page, 'leqra.getState().phase==="playing"' );
}
main::check(
    !scalar(
        grep {
            my $page = $_;
            !( ( value_eq( scalar( @{ main::state($page)->{'tanks'} } ), 4 ) ) )
        } @{$pages}
    ),
    'Four browser clients render shared arena'
);
main::check(
    !scalar(
        grep {
            my $page = $_;
            !( ( value_eq( main::state($page)->{'world'}, main::state( $pages->[0] )->{'world'} ) ) )
        } @{$pages}
    ),
    'Desktop and phones use identical arena dimensions'
);
$phone  = $pages->[1];
$cdp    = $contexts->[1]->newCDPSession($phone);
$st     = $phone->locator('#stickBase')->boundingBox();
$fb     = $phone->locator('#fireBtn')->boundingBox();
$cx     = ( $st->{'x'} + ( $st->{'width'} / 2 ) );
$cy     = ( $st->{'y'} + ( $st->{'height'} / 2 ) );
$points = [
    { 'x' => ( $cx + 32 ), 'y' => ( $cy - 9 ), 'id' => 11 },
    {
        'x'  => ( $fb->{'x'} + ( $fb->{'width'} / 2 ) ),
        'y'  => ( $fb->{'y'} + ( $fb->{'height'} / 2 ) ),
        'id' => 12
    }
];
$before = main::state($phone);
$angle  = (
    [
        map {
            my $t = $_;
            truth_value( ( value_eq( $t->{'id'}, 1 ) ) )
              ? ( $t->{'angle'} )
              : ()
        } @{ $before->{'tanks'} }
    ]->[0] // undef
);
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => $points } );
$Leqra::Browser::HANDLE->await( $phone->waitForTimeout(230) );
$after = main::state($phone);
main::check( evaluate_js( $phone->locator('#fireBtn'), 'e=>e.classList.contains("held")' ),
    'Touch fire button held while joystick active' );
main::check(
    ( !value_eq( evaluate_js( $phone->locator('#stickKnob'), 'e=>e.style.transform' ), 'translate(0,0)' ) ),
    'Touch joystick receives simultaneous pointer' );
main::check(
    (
        (
            abs(
                (
                    (
                        [
                            map {
                                my $t = $_;
                                truth_value( ( value_eq( $t->{'id'}, 1 ) ) )
                                  ? ( $t->{'angle'} )
                                  : ()
                            } @{ $after->{'tanks'} }
                        ]->[0] // undef
                    ) - $angle
                )
            ) > 0.02
        )
    ),
    'Touch steering changes server-backed tank heading'
);
main::check( ( ( $after->{'bulletCount'} > 0 ) ), 'Touch fire creates shared authoritative projectile' );
$phone->screenshot( { path => format_value( $out->child('mobile-controls-active.png') ) } );
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
$Leqra::Browser::HANDLE->await( $phone->waitForTimeout(80) );
main::check(
    ( !truth_value( evaluate_js( $phone->locator('#fireBtn'), 'e=>e.classList.contains("held")' ) ) ),
    'Touch release clears held fire' );
$old      = main::state( $pages->[3] )->{'online'};
$oldCount = evaluate_js( $pages->[3], '__sockets.length' );
evaluate_js( $pages->[3], '__sockets.at(-1).close(4000,"Test connection drop")' );
wait_js( $pages->[3], 'n=>__sockets.length>n && leqra.getState().online?.connected',
    $oldCount, { timeout => 9000 } );
$current = main::state( $pages->[3] )->{'online'};
main::check(
    (
        do {
            my $boolean_value = ( value_eq( $current->{'id'}, $old->{'id'} ) );
            truth_value($boolean_value)
              ? ( value_eq( $current->{'code'}, $old->{'code'} ) )
              : $boolean_value;
        }
    ),
    'Browser auto-reconnect preserves room and player'
);
$pages->[0]->locator('#pauseBtn')->click();
$tick = main::state( $pages->[0] )->{'online'}->{'serverTick'};
$Leqra::Browser::HANDLE->await( $pages->[0]->waitForTimeout(250) );
main::check( ( ( main::state( $pages->[0] )->{'online'}->{'serverTick'} > $tick ) ),
    'Opening online menu leaves server match running' );
$pages->[0]->locator('#onlineReturnBtn')->click();
for my $item ( @{ [ map { [ $_, $pages->[$_] ] } 0 .. $#{$pages} ] } ) {
    my $tuple_89_5 = $item;
    my $i          = $tuple_89_5->[0];
    my $page       = $tuple_89_5->[1];
    $page->screenshot(
        {
            path => format_value(
                $out->child( ( 'playing-' . $layouts->[$i]->[0] . 'x' . $layouts->[$i]->[1] . '.png' ) )
            )
        }
    );
}
$pages->[0]->locator('#pauseBtn')->click();
$pages->[0]->locator('#onlineLeaveBtn')->click();
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( main::state( $pages->[0] )->{'mode'}, 'solo' ) );
            truth_value($boolean_value)
              ? ( value_eq( main::state( $pages->[0] )->{'phase'}, 'menu' ) )
              : $boolean_value;
        }
    ),
    'Leaving online restores offline lobby'
);
$pages->[0]->locator('#playBtn')->click();
wait_js( $pages->[0], 'leqra.getState().phase==="playing"' );
main::check( ( value_eq( scalar( @{ main::state( $pages->[0] )->{'tanks'} } ), 3 ) ),
    'Solo bot squad still available' );
$pages->[0]->locator('#pauseBtn')->click();
$pages->[0]->locator('#quitBtn')->click();
$pages->[0]->locator('[data-mode=duel]')->click();
$pages->[0]->locator('#playBtn')->click();
wait_js( $pages->[0], 'leqra.getState().phase==="playing"' );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( scalar( @{ main::state( $pages->[0] )->{'tanks'} } ), 2 ) );
            truth_value($boolean_value)
              ? ( value_eq( main::state( $pages->[0] )->{'mode'}, 'duel' ) )
              : $boolean_value;
        }
    ),
    'Local two-player mode preserved'
);
main::check( ( !truth_value($errors) ), 'No JavaScript runtime errors' );
$report = {
    'checks_passed'     => scalar( @{$checks} ),
    'checks'            => $checks,
    'javascript_errors' => $errors,
    'layouts'           => $layouts,
    'isolated_assets'   => $args->{'isolated'},
    'browser_version'   => $browser->version()
};
$out->child('browser-results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", json_text( $report, 1 ) ), "\n" );
$browser->close();
