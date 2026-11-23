#!/usr/bin/env perl
# Compatible and breaking PWA upgrades against disposable HTTP fixtures.
use v5.34;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Leqra::Browser;
use Leqra::HTTPFixture;
use Digest::SHA;
use HTTP::Response;
use LWP::MediaTypes qw(guess_media_type);
$| = 1;

my $WEB = path($FindBin::Bin)->parent->child('web');
my @SHELL_FILES =
  qw(theme.js theme.css style.css favicon.svg netcode.js gamepads.js game.js callsigns.js infinite-maze.js infinite.js showcase-scene.js showcase.js pwa.js manifest.webmanifest sw.js);
my @ICON_FILES =
  qw(apple-touch-icon-512.png apple-touch-icon.png favicon-256.png icon-1024.png icon-192.png icon-512.png);

sub release {
    my (%options) = @_;
    my %files     = ( 'index.html' => $WEB->child('index.html')->slurp_raw );
    my ($version) = $files{'index.html'} =~ /src="assets\/(v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\/game\.js"/;
    die "Cannot find asset version\n" unless defined $version;
    my $base = "assets/$version/";
    $files{ $base . $_ } = $WEB->child( $base . $_ )->slurp_raw
      for @SHELL_FILES, @ICON_FILES;
    my $game = $base . 'game.js';
    my ($protocol) = $files{$game} =~ /const\s+GAME_PROTOCOL\s*=\s*(\d+)/;
    die "Cannot find game protocol\n" unless defined $protocol;

    if ( $options{breaking} ) {
        ++$protocol;
        $files{$game} =~ s/const\s+GAME_PROTOCOL\s*=\s*\d+/const GAME_PROTOCOL = $protocol/;
    }
    $files{ $base . 'style.css' } .= "\n#gameHeader{transform:translateY(-20px)!important}\n"
      if $options{stale_header};

    # Match appBuildID's path/length separators, order, and 64-bit hash prefix.
    my $digest = Digest::SHA->new(256);
    for my $name ( 'index.html', map { $base . $_ } @SHELL_FILES, @ICON_FILES ) {
        my $data = $files{$name};
        $digest->add( "web/$name\0" . length($data) . "\0", $data );
    }
    my $build = $version . '-' . substr( $digest->hexdigest, 0, 16 );
    my $html  = $files{'index.html'};
    $html =~ s/(\s(?:src|href)=")(assets\/[^"]+)/$1$2?build=$build/g;
    $html =~ s{</head>}{<meta name="leqra-build" content="$build">\n</head>};
    return {
        files    => \%files,
        version  => $version,
        base     => $base,
        protocol => 0 + $protocol,
        build    => $build,
        html     => $html,
        worker   => "'use strict';\nself.LEQRA_BUILD = '$build';\n" . $files{ $base . 'sw.js' }
    };
}

sub fixture {
    my ($breaking) = @_;
    my ( $old, $new ) =
      ( release( stale_header => 1 ), release( breaking => $breaking ) );
    assert_ok( $old->{build} ne $new->{build}, 'fixture releases differ' );
    my $server = Leqra::HTTPFixture->new(
        sub {
            my ( $request, $generation ) = @_;
            my $release = $generation ? $new : $old;
            my $url     = $request->uri->path;
            my ( $body, $mime, $cache );
            my %headers = ( 'X-Leqra-Build' => $release->{build} );
            if ( $url eq '/api/build' ) {
                $body = json_text( { map { $_ => $release->{$_} } qw(version build protocol) } );
                ( $mime, $cache ) = ( 'application/json', 'no-store' );
            }
            elsif ($url eq '/sw.js'
                || $url =~ m{\A/assets/v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?/sw\.js\z} )
            {
                ( $body, $mime, $cache ) =
                  ( $release->{worker}, 'text/javascript', 'no-store' );
                $headers{'Service-Worker-Allowed'} = '/';
            }
            elsif ( $url eq '/' || $url eq '/index.html' ) {
                ( $body, $mime, $cache ) = ( $release->{html}, 'text/html', 'no-cache, must-revalidate' );
                $headers{ETag} = '"' . $release->{build} . '"';
            }
            elsif ( $url eq '/legacy-registration.html' ) {
                $body =
                  q{<script>navigator.serviceWorker.register('/assets/v0.0.1/sw.js',{scope:'/'});</script>};
                ( $mime, $cache ) = ( 'text/html', 'no-store' );
            }
            elsif ( exists $release->{files}{ substr( $url, 1 ) } ) {
                $body = $release->{files}{ substr( $url, 1 ) };
                ( $mime, $cache ) = ( scalar guess_media_type($url), 'public, max-age=31536000, immutable' );
            }
            else {
                return HTTP::Response->new(404);
            }
            @headers{ 'Content-Type', 'Cache-Control', 'Content-Length' } = ( $mime, $cache, length $body );
            return HTTP::Response->new( 200, 'OK', [%headers], $body );
        }
    );
    return { old => $old, new => $new, server => $server, url => $server->url };
}
my $INIT = <<'JAVASCRIPT';
(() => {
    sessionStorage.setItem('pwaLoads', String(Number(sessionStorage.getItem('pwaLoads') || 0) + 1));
    window.pwaDocument = crypto.randomUUID();
    if (!localStorage.getItem('pwaFixtureSeeded')) {
        localStorage.setItem('leqra.name', 'UPDATE P1');
        localStorage.setItem('leqra.local2Name', 'UPDATE P2');
        localStorage.setItem('leqra.introTour.v1', '1');
        localStorage.setItem('pwaFixtureSeeded', '1');
    }
})();
JAVASCRIPT
my $PROBE = <<'JAVASCRIPT';
async () => {
    const worker = navigator.serviceWorker.controller;
    if (!worker) return null;
    return await new Promise((resolve, reject) => {
        const channel = new MessageChannel();
        const timeout = setTimeout(() => reject(Error('worker build probe timed out')), 3000);
        channel.port1.onmessage = event => {
            clearTimeout(timeout); channel.port1.close(); channel.port2.close(); resolve(event.data);
        };
        worker.postMessage({type:'LEQRA_BUILD_INFO'}, [channel.port2]);
    });
}
JAVASCRIPT

sub wait_for_worker {
    my ( $page, $build ) = @_;
    wait_js( $page, '!!navigator.serviceWorker.controller', undef, { timeout => 30000 } );
    my $deadline = time + 30;
    while ( time < $deadline ) {
        my $info = evaluate_js( $page, $PROBE );
        return if $info && $info->{build} eq $build;
        sleep 0.1;
    }
    die "Controller did not activate build $build\n";
}

sub setup_state {
    my ($page) = @_;
    return evaluate_js( $page, <<'JAVASCRIPT' );
() => ({
    roster: __test.localRoom.players.map(({id,kind,name,team,colorIndex,difficulty}) => ({kind,name,team,color:__test.teamColor(id,team,colorIndex),difficulty})),
    rules: __test.currentRules()
})
JAVASCRIPT
}

sub check_coherence {
    my ( $page, $release ) = @_;
    assert_ok( $page->locator('meta[name="leqra-build"]')->getAttribute('content') eq $release->{build},
        'HTML build is current' );
    assert_ok( evaluate_js( $page, 'leqra.version' ) eq $release->{version},   'client version is current' );
    assert_ok( evaluate_js( $page, 'leqra.protocol' ) == $release->{protocol}, 'client protocol is current' );
    assert_ok(
        evaluate_js( $page, "getComputedStyle(document.getElementById('gameHeader')).transform" ) eq 'none',
        'current stylesheet is active' );
    my $refs = evaluate_js( $page,
q{() => [...document.querySelectorAll('[src^="assets/"], [href^="assets/"]')].map(node => node.getAttribute('src') || node.getAttribute('href'))}
    );
    assert_ok(
        @$refs
          && !( grep { index( $_, $release->{base} ) != 0 || !/\Q?build=$release->{build}\E\z/ } @$refs ),
        $refs
    );
    assert_ok( evaluate_js( $page, $PROBE )->{build} eq $release->{build}, 'controller build is current' );
}

sub check_upgrade {
    my ( $browser, $engine, $screenshots, $breaking ) = @_;
    my $errors   = [];
    my $scenario = $breaking ? 'breaking' : 'compatible';
    my $fixture  = fixture($breaking);
    my $context  = $browser->newContext(
        {
            viewport       => { width => 1440, height => 1000 },
            serviceWorkers => 'allow'
        }
    );
    my $ok = eval {
        $context->addInitScript($INIT);
        my $page = $context->newPage;
        capture_event( $page, 'pageerror', $errors, '(error) => String(error)' );
        $page->goto( $fixture->{url} . '/?test' );
        wait_js( $page, '() => !!window.__test && !!window.leqra' );
        wait_for_worker( $page, $fixture->{old}{build} );
        assert_ok( evaluate_js( $page, 'leqra.protocol' ) == $fixture->{old}{protocol},
            'old protocol starts active' );
        assert_ok(
            evaluate_js( $page, "getComputedStyle(document.getElementById('gameHeader')).transform" ) eq
              'matrix(1, 0, 0, 1, 0, -20)',
            'stale stylesheet starts active'
        );
        assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 1,
            'initial controller claim did not reload' );

        # Use the actual room controls to leave public Infinity, add P2 and save paint.
        $page->locator('#infinityToggle')->uncheck;
        $page->locator('#roomPlayers > summary')->click;
        $page->locator('#addLocalBtn')->click;
        $page->locator('#roomRoster [data-tank-color="0"]')->selectOption('5');
        my $p2 = evaluate_js( $page, "__test.localRoom.players.find(p => p.kind === 'local').id" );
        $page->locator("#roomRoster [data-tank-color=\"$p2\"]")->selectOption('7');
        $page->locator('#roomSettings > summary')->click;
        $page->locator('[data-room-mode="koth"]')->click;
        $page->locator('#roomMapSize')->selectOption('huge');
        $page->locator('#startRoomBtn')->focus;
        my $expected    = setup_state($page);
        my $document_id = evaluate_js( $page, 'pwaDocument' );
        $page->locator('#startRoomBtn')->click;
        wait_js( $page, "leqra.getState().phase === 'playing'" );
        assert_ok( !evaluate_js( $page, 'leqra.prepareUpdate()' ), 'busy game declines an update' );

        $fixture->{server}->generation(1);
        evaluate_js( $page, <<'JAVASCRIPT' );
() => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted:true}));
}
JAVASCRIPT
        wait_for_worker( $page, $fixture->{new}{build} );

        # New worker is active and cached, but the running document stays on A.
        sleep 1.4;
        assert_ok( evaluate_js( $page, 'pwaDocument' ) eq $document_id, 'busy document stays active' );
        assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 1,
            'busy document did not reload' );
        assert_ok(
            $page->locator('meta[name="leqra-build"]')->getAttribute('content') eq $fixture->{old}{build},
            'busy document keeps its build' );
        my $phase = evaluate_js( $page, 'leqra.getState().phase' );
        assert_ok( scalar( grep( $_ eq $phase, qw(playing roundOver countdown) ) ),
            'game remains in a match' );
        my $keys = evaluate_js( $page, 'caches.keys()' );
        assert_ok( scalar( grep( $_ eq 'leqra-app-' . $fixture->{new}{build}, @$keys ) ), $keys );
        $page->screenshot(
            {
                path => '' . $screenshots->child("$engine-pwa-$scenario-busy.png")
            }
        ) if $screenshots;

        if ($breaking) {
            my $navigation = $page->waitForNavigation( { waitUntil => 'load', timeout => 15000 } );
            evaluate_js( $page, '__test.returnToRoom()' );
            $Leqra::Browser::HANDLE->await($navigation);
        }
        else {
            evaluate_js( $page, '__test.returnToRoom()' );
            sleep 1.4;
            assert_ok(
                evaluate_js( $page, 'pwaDocument' ) eq $document_id,
                'compatible build keeps the room document'
            );
            assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 1,
                'compatible build did not reload' );
            $page->reload( { waitUntil => 'load' } );
        }
        wait_js( $page, '() => !!window.__test && !!window.leqra' );
        wait_for_worker( $page, $fixture->{new}{build} );
        assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 2,
            'updated document loaded once' );
        assert_ok( evaluate_js( $page, 'pwaDocument' ) ne $document_id,
            'updated document has a new identity' );
        check_coherence( $page, $fixture->{new} );
        assert_ok( value_eq( setup_state($page), $expected ),
            { expected => $expected, actual => setup_state($page) } );
        sleep 1.4;
        assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 2,
            'update did not reload twice' );
        $page->screenshot(
            {
                path => '' . $screenshots->child("$engine-pwa-$scenario-updated.png")
            }
        ) if $screenshots;

        # Disable the actual network and reload the completed build B cache.
        $context->setOffline(JSON::PP::true);
        $page->reload( { waitUntil => 'load' } );
        wait_js( $page, '() => !!window.__test && !!window.leqra' );
        check_coherence( $page, $fixture->{new} );
        assert_ok( value_eq( setup_state($page), $expected ),
            { expected => $expected, actual => setup_state($page) } );
        assert_ok( evaluate_js( $page, 'Number(sessionStorage.pwaLoads)' ) == 3,
            'offline reload loaded once' );
        assert_ok( !@$errors, $errors );
        $context->setOffline(JSON::PP::false);
        my $expected_reload = $breaking ? 'one safe automatic reload' : 'adoption on manual reload';
        say "PASS $engine $scenario upgrade, $expected_reload and coherent offline assets";
        1;
    };
    my $error = $@;
    eval { $context->close };
    $fixture->{server}->stop;
    die $error unless $ok;
}

sub check_legacy_alias {
    my ( $browser, $engine ) = @_;
    my $fixture = fixture(0);
    my $context = $browser->newContext( { serviceWorkers => 'allow' } );
    my $ok      = eval {
        $context->addInitScript($INIT);
        my $page = $context->newPage;
        $page->goto( $fixture->{url} . '/legacy-registration.html' );
        wait_for_worker( $page, $fixture->{old}{build} );
        assert_ok(
            evaluate_js( $page, 'navigator.serviceWorker.controller.scriptURL' ) =~
              m{/assets/v0\.0\.1/sw\.js\z},
            'legacy worker alias controls the page'
        );
        $fixture->{server}->generation(1);
        evaluate_js( $page, 'async () => (await navigator.serviceWorker.ready).update()' );
        wait_for_worker( $page, $fixture->{new}{build} );

        # Legacy pages migrate their registration on fresh navigation.
        $page->goto( $fixture->{url} . '/?test' );
        wait_js( $page, '() => !!window.leqra' );
        wait_js( $page,
"navigator.serviceWorker.controller?.scriptURL.endsWith('/sw.js') && !navigator.serviceWorker.controller.scriptURL.includes('/assets/')"
        );
        check_coherence( $page, $fixture->{new} );
        say
          "PASS $engine legacy worker alias updates and migrates to stable registration on fresh navigation";
        1;
    };
    my $error = $@;
    eval { $context->close };
    $fixture->{server}->stop;
    die $error unless $ok;
}

my ( @engines, $screenshots, $server, $help );
GetOptions(
    'browser=s@'    => \@engines,
    'screenshots=s' => \$screenshots,
    'server=s'      => \$server,
    'help|h'        => \$help
) or die "Usage: pwa_update_browser.pl [--browser chromium|webkit] [--screenshots DIR] [--server URL]\n";
if ($help) {
    say 'Usage: pwa_update_browser.pl [--browser chromium|webkit] [--screenshots DIR] [--server URL]';
    exit;
}
die "Unexpected arguments: @ARGV\n" if @ARGV;
@engines = ('chromium') unless @engines;
die "Unknown browser $_\n" for grep { !/\A(?:chromium|webkit)\z/ } @engines;
if ($server) {
    $server =~ s{/$}{};
    my $info    = decode_json( request_ok("$server/api/build")->decoded_content );
    my $release = release();
    assert_ok( $info->{build} eq $release->{build} && $info->{protocol} == $release->{protocol},
        [ 'fixture and compiled server metadata differ', $info ] );
}
if ($screenshots) {
    $screenshots = path($screenshots)->realpath;
    assert_ok( $screenshots->is_dir, 'screenshot directory must already exist' );
    my $root = $WEB->parent(2)->realpath;
    assert_ok( index( "$screenshots/", "$root/" ) != 0,
        'generated screenshots must stay outside the repository' );
}
my $pw = start_playwright();
for my $engine (@engines) {
    my $browser = $pw->launch(
        type     => ( $engine eq 'chromium' ? 'chrome' : $engine ),
        headless => 1
    );
    my $ok = eval {
        check_upgrade( $browser, $engine, $screenshots, 0 );
        check_upgrade( $browser, $engine, $screenshots, 1 );
        check_legacy_alias( $browser, $engine );
        1;
    };
    my $error = $@;
    eval { $browser->close };
    die $error unless $ok;
}
