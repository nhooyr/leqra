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
    $a,      $ap,       $assets, $b,        $before, $box,  $c,    $checks, $code,
    $colors, $contexts, $errors, $expected, $hc,     $host, $html, $i,      $js,
    $moved,  $out,      $p,      $pages,    $pw,     $q,    $qc,   $rgba,   $root,
    $scheme, $size,     $state,  $stored,   $t,      $text, $vc,   $viewer, $web
);

# Appearance and gameplay regression using real Chromium media emulation.
# Navigation is restricted in this environment, so exact assets and storage/URL
# adapters are injected. Online checks use the opt-in loopback Go test fixture.
# Run: perl tests/theme43_browser.pl --url http://127.0.0.1:8431 --output test-output/theme43
$ap = {};
$a  = do {
    my %args = ( 'url' => 'http://127.0.0.1:8431', 'output' => 'test-output/theme43' );
    my $help;
    GetOptions(
        'url=s'    => \$args{'url'},
        'output=s' => \$args{'output'},
        'help|h'   => \$help
      )
      or die 'Usage: perl theme43_browser.pl --url --output
';
    if ($help) {
        print 'Usage: perl theme43_browser.pl --url --output
';
        exit 0;
    }
    \%args;
};
$root   = path($0)->absolute->parent(2);
$web    = $root->child('web');
$assets = asset_directory($web);
$out    = path( $a->{'output'} );
$out->mkpath;
$html =
  replace_re( '<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8 );
$html = replace_text(
    $html,
    '</head>',
    (
        ( ( '<style>' . $assets->child('theme.css')->slurp_utf8 ) . $assets->child('style.css')->slurp_utf8 )
        . '</style></head>'
    )
);
$js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1 );
$i  = rindex( $js, '})()' );
$js =
  ( ( substr( $js, 0, $i - 0 ) . '})(window.__location,window.__history);' ) . substr( $js, ( $i + 4 ) ) );
$checks   = [];
$errors   = [];
$pages    = [];
$contexts = [];

sub wait {
    my ( $p, $expression, $kwargs ) = @_;
    $kwargs //= {};
    return wait_js( $p, $expression, undef, { polling => 50 } );
}

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub load {
    my ( $b, $size, $scheme, $stored, $blocked, $live, $code, $watch ) = @_;
    my ( $c, $h, $mobile, $name, $p, $query, $w );
    $size    //= [ 1365, 950 ];
    $scheme  //= 'dark';
    $stored  //= undef;
    $blocked //= JSON::PP::false;
    $live    //= JSON::PP::false;
    $code    //= undef;
    $watch   //= JSON::PP::false;
    my $tuple_22_1 = $size;
    $w      = $tuple_22_1->[0];
    $h      = $tuple_22_1->[1];
    $mobile = (
        do {
            my $boolean_value = ( ( $w < 760 ) );
            truth_value($boolean_value) ? $boolean_value : ( ( $h < 620 ) );
        }
    );
    $c = $b->newContext(
        {
            viewport          => { 'width' => $w, 'height' => $h },
            colorScheme       => $scheme,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 ),
            hasTouch          => $mobile,
            isMobile          => $mobile
        }
    );
    push( @{$contexts}, $c );
    $p = $c->newPage();
    push( @{$pages}, $p );
    $p->setDefaultTimeout(9000);
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->setContent($html);
    $query = { 'test' => '1' };

    if ( truth_value($code) ) {
        $query->{'room'} = $code;
    }
    if ( truth_value($watch) ) {
        $query->{'spectate'} = '1';
    }
    evaluate_js(
        $p,
'a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};window.__store=a.stored;window.__sent=[];
 const store=d=>({getItem:k=>{if(a.blocked)throw Error(\'denied\');return d[k]??null;},setItem:(k,v)=>{if(a.blocked)throw Error(\'denied\');d[k]=String(v);},removeItem:k=>{if(a.blocked)throw Error(\'denied\');delete d[k];}});
 Object.defineProperty(window,\'localStorage\',{value:store(__store)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});
 if(!a.live)window.requestAnimationFrame=()=>0;
 const WS=WebSocket;window.WebSocket=class extends WS{send(v){__sent.push(JSON.parse(v));return super.send(v)}};
 }',
        {
            'url'    => ( ( $a->{'url'} . '/?' ) . query_string($query) ),
            'stored' => (
                truth_value( ( defined($stored) ) )
                ? $stored
                : { 'leqra.name' => 'PILOT', 'leqra.muted' => '1' }
            ),
            'blocked' => $blocked,
            'live'    => $live
        }
    );
    for $name ( @{ [ 'theme.js', 'netcode.js' ] } ) {
        $p->addScriptTag( { content => $assets->child($name)->slurp_utf8 } );
    }
    $p->addScriptTag( { content => $js } );
    main::wait( $p, 'window.__test && leqra.version==="4.3.0"' );
    evaluate_js( $p, '__test.render()' );
    return [ $p, $c ];
}

sub shape {
    my ($p) = @_;
    return evaluate_js( $p,
'()=>{const e=document.querySelector(\'#arenaWrap\'),r=e.getBoundingClientRect(),c=document.querySelector(\'#arena\');return [r.x,r.y,r.width,r.height,c.width,c.height];}'
    );
}

sub skin {
    my ($p) = @_;
    return evaluate_js( $p, 'leqra.getState().appearance' );
}

sub physical {
    my ($p) = @_;
    return evaluate_js( $p,
        'JSON.stringify({state:leqra.getState(),walls:__test.walls,pickups:__test.pickups})' );
}

sub normal_state {
    my ($p) = @_;
    return evaluate_js( $p,
'()=>{const s=leqra.getState();delete s.appearance;return JSON.stringify({s,walls:__test.walls,pickups:__test.pickups,bullets:__test.bullets});}'
    );
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
eval {
    for $scheme ( @{ [ 'dark', 'light' ] } ) {
        my $tuple_45_3 = main::load( $b, undef, $scheme, undef, undef, undef, undef, undef );
        $p = $tuple_45_3->[0];
        $c = $tuple_45_3->[1];
        main::check( ( value_eq( main::skin($p), { 'preference' => 'auto', 'resolved' => $scheme } ) ),
            ( $scheme . ': clean profile follows browser' ) );
        $colors = evaluate_js( $p,
'()=>{const r=getComputedStyle(document.documentElement),button=getComputedStyle(document.querySelector(\'#startRoomBtn\'));return {accent:r.getPropertyValue(\'--accent\').trim(),scheme:r.colorScheme,background:button.backgroundColor,text:button.color,meta:document.querySelector(\'meta[name="theme-color"]\').content};}'
        );
        main::check(
            (
                value_eq(
                    $colors->{'accent'},
                    (
                        truth_value( ( value_eq( $scheme, 'dark' ) ) )
                        ? '#39ff14'
                        : '#a100ff'
                    )
                )
            ),
            ( $scheme . ': exact requested neon accent' )
        );
        main::check( ( value_eq( $colors->{'scheme'}, $scheme ) ),
            ( $scheme . ': native inputs use matching color-scheme' ) );
        main::check(
            (
                value_eq(
                    $colors->{'meta'},
                    (
                        truth_value( ( value_eq( $scheme, 'dark' ) ) )
                        ? '#111619'
                        : '#f5f2fa'
                    )
                )
            ),
            ( $scheme . ': browser theme-color follows appearance' )
        );
        $p->locator('#roomControlsBtn')->click();
        main::check( ( value_eq( $p->locator('#themeMode')->inputValue(), 'auto' ) ),
            ( $scheme . ': settings default to Auto' ) );
        main::check(
            ( value_eq( $p->locator('#themeMode option')->count(), 3 ) ),
            ( $scheme . ': exactly Auto / Dark / Light choices' )
        );
        $p->locator('#themeMode')->selectOption(
            (
                truth_value( ( value_eq( $scheme, 'dark' ) ) )
                ? 'light'
                : 'dark'
            )
        );
        $expected =
          ( truth_value( ( value_eq( $scheme, 'dark' ) ) ) ? 'light' : 'dark' );
        main::check(
            ( value_eq( main::skin($p)->{'resolved'}, $expected ) ),
            ( $scheme . ': manual UI selection takes effect immediately' )
        );
        $p->emulateMedia( { colorScheme => $scheme } );
        main::check(
            ( value_eq( main::skin($p)->{'resolved'}, $expected ) ),
            ( $scheme . ': explicit choice ignores system' )
        );
        $stored = evaluate_js( $p, '__store' );
        my $tuple_59_32 = main::load( $b, undef, $scheme, $stored, undef, undef, undef, undef );
        $q  = $tuple_59_32->[0];
        $qc = $tuple_59_32->[1];
        main::check(
            (
                do {
                    my $boolean_value =
                      ( value_eq( main::skin($q)->{'resolved'}, $expected ) );
                    truth_value($boolean_value)
                      ? ( value_eq( main::skin($q)->{'preference'}, $expected ) )
                      : $boolean_value;
                }
            ),
            ( $scheme . ': manual selection survives a fresh page load' )
        );
        $qc->close();
        $p->locator('#themeMode')->selectOption('auto');
        $p->emulateMedia( { colorScheme => $expected } );
        main::wait( $p, '(s)=>leqraTheme.resolved===s', { 'arg' => $expected } );
        main::check(
            ( value_eq( main::skin($p)->{'preference'}, 'auto' ) ),
            ( $scheme . ': Auto resumes live preference tracking' )
        );
        $p->locator('[data-close-dialog="controlsDialog"]')->click();
        $p->locator('#joinOtherBtn')->click();
        main::check(
            evaluate_js(
                $p,
'getComputedStyle(document.querySelector("#joinRoomBtn")).backgroundColor===getComputedStyle(document.querySelector("#createRoomBtn")).backgroundColor'
            ),
            ( $scheme . ': Join and Create still match' )
        );
        $c->close();
    }
    my $tuple_67_2 = main::load( $b, undef, 'light', undef, JSON::PP::true, undef, undef, undef );
    $p = $tuple_67_2->[0];
    $c = $tuple_67_2->[1];
    $p->locator('#roomControlsBtn')->click();
    $p->locator('#themeMode')->selectOption('dark');
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( main::skin($p)->{'resolved'}, 'dark' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $p->locator('#themeStatus')->innerText(), 'Session only' ) )
                  : $boolean_value;
            }
        ),
        'Blocked storage: manual choice works and save limitation is shown'
    );
    $c->close();
    my $tuple_69_2 = main::load(
        $b, undef, 'light',
        {
            'leqra.theme.v1'    => 'invalid',
            'leqra.feedback.v1' => '{"audio":false,"fps":true}',
            'leqra.muted'       => '1'
        },
        undef, undef, undef, undef
    );
    $p = $tuple_69_2->[0];
    $c = $tuple_69_2->[1];
    main::check( ( value_eq( main::skin($p)->{'preference'}, 'auto' ) ),
        'Invalid saved theme falls back to Auto' );
    main::check( evaluate_js( $p, 'JSON.parse(__store["leqra.feedback.v1"]).audio===false' ),
        'Theme startup preserves prior audio preferences' );
    $c->close();
    for $size ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        my $tuple_74_3 = main::load( $b, $size, undef, undef, undef, undef, undef, undef );
        $p = $tuple_74_3->[0];
        $c = $tuple_74_3->[1];
        $p->locator('#addLocalBtn')->click();
        $p->locator('#startRoomBtn')->click();
        evaluate_js( $p,
            '__test.setPhase(\'playing\');__test.tanks.forEach(t=>t.human=true);__test.updateHUD(true)' );
        $state = main::normal_state($p);
        $box   = main::shape($p);

        for $scheme ( @{ [ 'light', 'dark' ] } ) {
            evaluate_js( $p, '(s)=>{leqraTheme.setPreference(s);__test.render();}', $scheme );
            main::check( ( value_eq( main::normal_state($p), $state ) ),
                ( $size . ' ' . $scheme . ': maze, tanks, shots, scores and rules unchanged' ) );
            main::check( ( value_eq( main::shape($p), $box ) ),
                ( $size . ' ' . $scheme . ': canvas and HUD geometry unchanged' ) );
            main::check(
                evaluate_js( $p, 'document.body.scrollWidth<=innerWidth+1' ),
                ( $size . ' ' . $scheme . ': no horizontal overflow' )
            );
            main::check(
                evaluate_js(
                    $p,
'()=>{__test.renderPowerLegend();return [...document.querySelectorAll(\'.power-list canvas\')].every(e=>{const f=document.createElement(\'canvas\');f.width=e.width;f.height=e.height;const c=f.getContext(\'2d\');c.setTransform(f.width/26,0,0,f.height/26,f.width/2,f.height/2);__test.powerIcon(e.dataset.powerIcon,c);return f.toDataURL()===e.toDataURL();});}'
                ),
                ( $size . ' ' . $scheme . ': all ten legend/maze icons match' )
            );
            $rgba = evaluate_js( $p,
                'Array.from(document.querySelector("#arena").getContext("2d").getImageData(1,1,1,1).data)' );
            main::check(
                (
                    value_eq(
                        array_slice( $rgba, 0, 3 ),
                        (
                            truth_value( ( value_eq( $scheme, 'light' ) ) )
                            ? [ 229, 222, 238 ]
                            : [ 16, 24, 30 ]
                        )
                    )
                ),
                ( $size . ' ' . $scheme . ': canvas changes with the page' )
            );
            $p->screenshot(
                {
                    path => format_value(
                        $out->child(
                            ( 'playing-' . $scheme . '-' . $size->[0] . 'x' . $size->[1] . '.png' )
                        )
                    )
                }
            );

            for $t ( @{ [ 'cannon', 'speed', 'shield', 'scope', 'ghost' ] } ) {
                evaluate_js(
                    $p,
'(t)=>{for(const tank of __test.tanks.filter(t=>t.localIndex===1||t.id===0))__test.grantPower(tank,t);__test.updateHUD(true);__test.render()}',
                    $t
                );
            }
            main::check( ( value_eq( main::shape($p), $box ) ),
                ( $size . ' ' . $scheme . ': stacked buffs still cannot resize arena' ) );
            $state = main::normal_state($p);
            evaluate_js( $p, 'document.querySelector("#controlsDialog").showModal()' );
            $p->screenshot(
                {
                    path => format_value(
                        $out->child(
                            ( 'appearance-' . $scheme . '-' . $size->[0] . 'x' . $size->[1] . '.png' )
                        )
                    )
                }
            );
            main::check( evaluate_js( $p->locator('#themeMode'), '(e)=>e.scrollWidth<=e.clientWidth+1' ),
                ( $size . ' ' . $scheme . ': theme selector fits' ) );
            $p->locator('[data-close-dialog="controlsDialog"]')->click();
            $state = main::normal_state($p);
        }
        evaluate_js( $p, 'leqraTheme.setPreference(\'auto\')' );
        $p->keyboard()->down('w');
        $before = main::normal_state($p);
        $p->emulateMedia( { colorScheme => 'light' } );
        main::wait( $p, 'leqraTheme.resolved==="light"' );
        main::check(
            ( value_eq( main::normal_state($p), $before ) ),
            ( $size . ': automatic switch does not reset live game' )
        );
        $moved = evaluate_js( $p,
'()=>{const t=__test.tanks[0],old=[t.x,t.y];__test.humanControl(t,.05);return Math.hypot(t.x-old[0],t.y-old[1])>0;}'
        );
        $p->keyboard()->up('w');
        main::check( $moved, ( $size . ': held movement survives automatic change' ) );
        evaluate_js( $p, '__test.finishMatch(0)' );
        $p->screenshot(
            {
                path => format_value(
                    $out->child( ( 'victory-light-' . $size->[0] . 'x' . $size->[1] . '.png' ) )
                )
            }
        );
        main::check(
            (
                do {
                    my $boolean_value = evaluate_js( $p->locator('#victoryDialog'), '(e)=>e.open' );
                    truth_value($boolean_value)
                      ? $p->locator('#victoryStats')->isVisible()
                      : $boolean_value;
                }
            ),
            ( $size . ': themed congratulations and post-match stats remain visible' )
        );
        $text = $p->locator('#cooldownText1')->innerText();
        evaluate_js( $p, 'leqraTheme.setPreference(\'dark\');__test.updateHUD(true)' );
        main::check(
            (
                     value_eq( $p->locator('#cooldownText1')->innerText(), $text )
                  && value_eq( $text, 'MATCH COMPLETE' )
            ),
            ( $size . ': theme switch cannot restart the completed cooldown' )
        );
        $c->close();
    }
    my $tuple_102_2 = main::load( $b, undef, 'dark', { 'leqra.name' => 'HOST', 'leqra.muted' => '1' },
        undef, JSON::PP::true, undef, undef );
    $host = $tuple_102_2->[0];
    $hc   = $tuple_102_2->[1];
    $host->locator('#addLocalBtn')->click();
    $host->locator('#copyInviteBtn')->click();
    main::wait( $host, 'leqra.getState().online?.connected' );
    $code = evaluate_js( $host, '__test.online.code' );
    my $tuple_104_2 = main::load(
        $b, [ 320, 568 ],
        'light', { 'leqra.name' => 'VIEWER', 'leqra.muted' => '1' },
        undef, JSON::PP::true, $code, JSON::PP::true
    );
    $viewer = $tuple_104_2->[0];
    $vc     = $tuple_104_2->[1];
    main::check( ( !truth_value( evaluate_js( $viewer, 'leqra.getState().online?.connected||false' ) ) ),
        'Spectator link still asks for callsign before joining' );
    $viewer->locator('#joinRoomBtn')->click();
    main::wait( $viewer, 'leqra.getState().online?.spectating' );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( main::skin($host)->{'resolved'}, 'dark' ) );
                truth_value($boolean_value)
                  ? ( value_eq( main::skin($viewer)->{'resolved'}, 'light' ) )
                  : $boolean_value;
            }
        ),
        'Online player and spectator can use different themes in one room'
    );
    $host->locator('#startRoomBtn')->click();
    main::wait( $host,   'leqra.getState().phase==="playing"' );
    main::wait( $viewer, 'leqra.getState().phase==="playing"' );
    evaluate_js( $host,
'window.__socketBefore=__test.online.socket;window.__predictorBefore=__test.online.predictor;window.__generationBefore=__test.online.generation;window.__idBefore=__test.online.id;window.__sent=[]'
    );
    $host->keyboard()->down('w');
    $host->keyboard()->down('ArrowUp');
    $host->emulateMedia( { colorScheme => 'light' } );
    main::wait( $host, 'leqraTheme.resolved==="light"' );
    $host->keyboard()->up('w');
    $host->keyboard()->up('ArrowUp');
    main::check(
        evaluate_js(
            $host,
'__test.online.socket===__socketBefore && __test.online.predictor===__predictorBefore && __test.online.generation===__generationBefore && __test.online.id===__idBefore'
        ),
        'Live appearance change preserves socket, local predictor, arena generation and identity'
    );
    main::check(
        evaluate_js( $host, '__sent.every(m=>["input","ping"].includes(m.type))' ),
        'Appearance switch sends no room edits, restarts or extra matchmaking messages'
    );
    main::check( evaluate_js( $viewer, 'leqraTheme.preference==="auto" && leqraTheme.resolved==="light"' ),
        'Host changing appearance cannot override spectator preference' );
    $host->locator('#chatBtn')->click();
    $host->locator('#chatInput')->fill('Purple and green: same room!');
    $host->locator('#chatSendBtn')->click();
    $viewer->locator('#chatBtn')->click();
    main::wait( $viewer, 'document.querySelector("#chatMessages").textContent.includes("Purple and green")' );
    main::check( JSON::PP::true, 'Room chat works across light/dark clients and spectators' );
    $viewer->screenshot( { path => format_value( $out->child('chat-light-320.png') ) } );
    $viewer->locator('#chatCloseBtn')->click();
    $viewer->screenshot(
        {
            path => format_value( $out->child('online-spectator-light-320.png') )
        }
    );
    $host->locator('#chatCloseBtn')->click();
    evaluate_js( $host, 'leqraTheme.setPreference("dark")' );
    $host->screenshot( { path => format_value( $out->child('online-player-dark.png') ) } );
    $before = evaluate_js( $host, '__test.online.id' );
    evaluate_js( $host, '__test.online.socket.close(4000,"theme regression")' );
    main::wait( $host, 'leqra.getState().online?.connected', { 'timeout' => 15000 } );
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( evaluate_js( $host, '__test.online.id' ), $before ) );
                truth_value($boolean_value)
                  ? ( value_eq( main::skin($host)->{'resolved'}, 'dark' ) )
                  : $boolean_value;
            }
        ),
        'Reconnect retains identity and manual appearance'
    );
    $hc->close();
    $vc->close();
    main::check( ( !truth_value($errors) ), 'No JavaScript errors across theme and live-room checks' );
    1;
};
my $caught_error = $@;
for $p ( @{$pages} ) {
    if ( truth_value( ( !truth_value( $p->isClosed() ) ) ) ) {
        eval {
            $p->screenshot( { path => format_value( $out->child('failure.png') ) } );
            1;
        };
        if ($@) {
        }
    }
}
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version' => '4.3.0',
            'passed'  => scalar( @{$checks} ),
            'checks'  => $checks,
            'errors'  => $errors
        },
        1
    )
);
die $caught_error if $caught_error;
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
