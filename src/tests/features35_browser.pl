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
    $ap,       $args,  $assets, $before,    $browser, $c,     $checks, $code,
    $contexts, $count, $dims,   $elsewhere, $errors,  $guest, $host,   $i,
    $late,     $n,     $ok,     $out,       $p,       $pw,    $report, $root,
    $saved,    $size,  $viewer, $watch,     $web
);

# v3.5 shipped assets + real loopback Go WebSockets; synthetic URL/storage adapters.
$ap   = {};
$args = do {
    my %args = (
        'url'    => 'http://127.0.0.1:18790',
        'output' => 'test-output/features35'
    );
    my $help;
    GetOptions(
        'url=s'    => \$args{'url'},
        'output=s' => \$args{'output'},
        'help|h'   => \$help
      )
      or die 'Usage: perl features35_browser.pl --url --output
';
    if ($help) {
        print 'Usage: perl features35_browser.pl --url --output
';
        exit 0;
    }
    \%args;
};
$root   = path($0)->absolute->parent(2);
$web    = $root->child('web');
$assets = asset_directory($web);
$out    = path( $args->{'output'} );
$out->mkpath;
$checks = [];
$errors = [];

sub check {
    my ( $v, $label ) = @_;
    if ( truth_value( ( !truth_value($v) ) ) ) {
        die json_text($label);
    }
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub state {
    my ($p) = @_;
    return evaluate_js( $p, 'leqra.getState()' );
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$contexts = [];

sub load {
    my ( $name, $size, $code, $watch, $storage ) = @_;
    my ( $c, $html, $i, $js, $mobile, $p, $url );
    $name    //= 'HOST';
    $size    //= [ 1365, 950 ];
    $code    //= undef;
    $watch   //= JSON::PP::false;
    $storage //= undef;
    $mobile = (
        do {
            my $boolean_value = ( ( $size->[0] < 760 ) );
            truth_value($boolean_value)
              ? $boolean_value
              : ( ( $size->[1] < 620 ) );
        }
    );
    $c = $browser->newContext(
        {
            viewport          => { 'width' => $size->[0], 'height' => $size->[1] },
            isMobile          => $mobile,
            hasTouch          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 )
        }
    );
    push( @{$contexts}, $c );
    $p = $c->newPage();
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->on( 'dialog', 'arguments[0].accept();' );
    $html = replace_re( '<link[^>]*>',                         '', $web->child('index.html')->slurp_utf8 );
    $html = replace_re( '<script src="[^"]+" defer></script>', '', $html );
    $html = replace_text( $html, '</head>',
        ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' ) );
    $p->setContent($html);
    $url = (
        'http://game.test/tanks/?test=1'
          . (
            truth_value($code)
            ? (
                '&'
                  . query_string(
                    {
                        'room' => $code,
                        %{ ( truth_value($watch) ? { 'spectate' => 1 } : {} ) }
                    }
                  )
              )
            : ''
          )
    );
    evaluate_js(
        $p,
'([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({\'leqra.name\':name,\'leqra.muted\':\'1\'},storage||{});Object.defineProperty(window,\'localStorage\',{value:store(__store)});window.__session={};Object.defineProperty(window,\'sessionStorage\',{value:store(__session)});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{window.__copied=v}}});}',
        [ $url, ( replace_text( $args->{'url'}, 'http:', 'ws:' ) . '/ws' ), $name, $storage ]
    );
    $js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
    $i  = rindex( $js, '})()' );
    $js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location);' ) . substr( $js, ( $i + 4 ) ) );
    $p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.leqra' );
    return $p;
}

sub conn {
    my ($p) = @_;
    wait_js( $p, 'leqra.getState().online?.connected', undef, { timeout => 12000 } );
}

sub start {
    my ($p) = @_;
    $p->locator('#startRoomBtn')->click();
    wait_js( $p, 'leqra.getState().phase==="playing"', undef, { timeout => 9000 } );
}

sub rules {
    my ( $p, $values ) = @_;
    my ( $control, $e, $k, $selected_mode, $selector, $setting, $v, $value );
    $values //= {};
    $selected_mode = splice( @{$values}, 'mode', 1 );
    if ( truth_value( ( defined($selected_mode) ) ) ) {
        $p->locator( ( ( '[data-room-mode="' . $selected_mode ) . '"]' ) )->click();
        wait_js( $p, '(mode)=>leqra.getState().rules.mode===mode', $selected_mode, {} );
    }
    for my $item ( @{ [ [ 'teamMode', '#roomTeamMode' ], [ 'mapSize', '#roomMapSize' ] ] } ) {
        my $tuple_28_6 = $item;
        my $setting    = $tuple_28_6->[0];
        my $selector   = $tuple_28_6->[1];
        my $value      = splice( @{$values}, $setting, 1 );
        if ( truth_value( ( defined($value) ) ) ) {
            my $control = $p->locator($selector);
            if ( truth_value( $control->isDisabled() ) ) {
                assert_ok( ( value_eq( $control->inputValue(), format_value($value) ) ),
                    'control.input_value()==str(value)' );
            }
            else {
                $control->selectOption( format_value($value) );
                wait_js( $p, '([key,value])=>leqra.getState().rules[key]===value', [ $setting, $value ], {} );
            }
        }
    }
    $p->locator('#roomRulesBtn')->click();
    for my $item ( @{ [ map { [ $_, $values->{$_} ] } keys %{$values} ] } ) {
        my $tuple_35_6 = $item;
        my $k          = $tuple_35_6->[0];
        my $v          = $tuple_35_6->[1];
        my $e          = $p->locator( ( '#rule-' . $k ) );
        if ( truth_value( ( contains_value( [ 'mapSize', 'teamMode', 'pickupRate' ], $k ) ) ) ) {
            if ( truth_value( $e->isDisabled() ) ) {
                assert_ok( ( value_eq( $e->inputValue(), format_value($v) ) ), 'e.input_value()==str(v)' );
            }
            else {
                $e->selectOption( format_value($v) );
            }
        }
        else {
            $e->fill( format_value($v) );
        }
    }
    $p->locator('#applyRulesBtn')->click();
    wait_js( $p, '!document.querySelector("#rulesDialog").open' );
}

sub arena {
    my ($p) = @_;
    return $p->locator('#arenaWrap')->boundingBox();
}

sub settings {
    my ($p) = @_;
    $p->locator('#roomControlsBtn')->click();
}

sub closeControls {
    my ($p) = @_;
    $p->locator('[data-close-dialog="controlsDialog"]')->click();
}

sub chat {
    my ( $p, $text ) = @_;
    if ( truth_value( ( !truth_value( $p->locator('#chatPanel')->isVisible() ) ) ) ) {
        $p->locator('#chatBtn')->click();
    }
    $p->locator('#chatInput')->fill($text);
    $p->locator('#chatInput')->press('Enter');
    wait_js( $p, '!document.querySelector("#chatSendBtn").disabled', undef, { timeout => 4000 } );
}

sub message {
    my ( $p, $text ) = @_;
    wait_js( $p, 'text=>[...document.querySelectorAll("#chatMessages p")].some(p=>p.textContent===text)',
        $text, {} );
}

sub active {
    my ($p) = @_;
    return scalar( @{ main::state($p)->{'room'}->{'players'} } );
}

sub snap {
    my ( $p, $name ) = @_;
    my ( $bounds, $vp );
    if ( truth_value( ( index( $name, 'chat-' ) == 0 ) ) ) {
        $bounds = $p->locator('#chatPanel')->boundingBox();
        $vp     = $p->viewportSize();
        main::check(
            (
                do {
                    my $boolean_value = ( ( $bounds->{'x'} >= 0 ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value =
                          ( ( ( $bounds->{'x'} + $bounds->{'width'} ) <= ( $vp->{'width'} + 1 ) ) );
                        truth_value($boolean_value)
                          ? ( ( ( $bounds->{'y'} + $bounds->{'height'} ) <= ( $vp->{'height'} + 1 ) ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( 'Chat fits viewport ' . $name )
        );
        main::check(
            (
                (
                    (
                        $p->locator('#pauseBtn')->boundingBox()->{'x'} +
                          $p->locator('#pauseBtn')->boundingBox()->{'width'}
                    ) <= ( $vp->{'width'} + 1 )
                )
            ),
            ( 'Header actions fit ' . $name )
        );
    }
    $p->screenshot( { path => format_value( $out->child( ( $name . '.png' ) ) ) } );
}
eval {
    for $size ( @{ [ [ 1365, 950 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        $p = main::load( undef, $size, undef, undef, undef );
        main::check( ( value_eq( main::state($p)->{'rules'}->{'mapSize'}, 'large' ) ),
            ( 'Default 12x10 ' . format_value($size) ) );
        main::check( $p->locator('#chatBtn')->isHidden(),
            ( 'Local room has no misleading online chat ' . format_value($size) ) );
        main::check( $p->locator('#fpsIndicator')->isHidden(), ( 'FPS opt-in ' . format_value($size) ) );
        while ( truth_value( ( ( main::active($p) < 7 ) ) ) ) {
            $p->locator('#addBotBtn')->click();
        }
        $p->locator('#addLocalBtn')->click();
        main::check( ( value_eq( main::active($p), 8 ) ),
            ( 'Eight mixed local seats ' . format_value($size) ) );
        main::check( $p->locator('#addBotBtn')->isDisabled(),
            ( 'Ninth tank disabled ' . format_value($size) ) );
        main::check( ( substr( $p->locator('#seatCount')->innerText(), -length('/ 8') ) eq '/ 8' ),
            ( 'Room capacity label ' . format_value($size) ) );
        main::rules(
            $p,
            {
                'mapSize'     => 'huge',
                'mode'        => 'koth',
                'teamMode'    => 'ffa',
                'timeLimit'   => 300,
                'scoreTarget' => 300
            }
        );
        main::settings($p);
        $p->locator('#showFPS')->check();
        $p->locator('#performanceMode')->check();
        main::closeControls($p);
        $Leqra::Browser::HANDLE->await( $p->waitForTimeout(900) );
        main::check( ( contains_value( $p->locator('#fpsIndicator')->innerText(), 'fps:' ) ),
            ( 'FPS reading ' . format_value($size) ) );
        $saved = evaluate_js( $p, '__store' );
        main::check( decode_json( $saved->{'leqra.feedback.v1'} )->{'fps'},
            ( 'FPS saved ' . format_value($size) ) );
        main::snap( $p, ( 'room-' . format_value( $size->[0] ) ) );
        main::start($p);
        main::check(
            (
                do {
                    my $boolean_value = ( value_eq( scalar( @{ main::state($p)->{'tanks'} } ), 8 ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( main::state($p)->{'world'}->{'cols'}, 14 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( main::state($p)->{'world'}->{'rows'}, 12 ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( 'Eight tanks on 14x12 ' . format_value($size) )
        );
        evaluate_js( $p,
'()=>{__test.setPhase(\'paused\');__test.clearBullets();for(const t of __test.tanks){t.alive=true;t.invulnerable=999;}__test.updateHUD(true);}'
        );
        $dims = main::arena($p);
        evaluate_js( $p,
'()=>{for(const t of __test.tanks)if(t.human){__test.grantPower(t,\'speed\');t.shield=10;}__test.updateHUD(true);}'
        );
        $Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
        main::check( ( value_eq( main::arena($p), $dims ) ),
            ( 'Buffs keep stable arena ' . format_value($size) ) );
        main::check( $p->locator('#pilotLoadout2')->isVisible(),
            ( 'High-seat local player ammo ' . format_value($size) ) );
        $ok = evaluate_js( $p,
'()=>{const t=__test.tanks.find(t=>t.human&&t.id!==0);__test.clearInput();__test.clearBullets();t.cooldown=0;t.invulnerable=0;window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:\'Space\',bubbles:true}));__test.humanControl(t,1/120);window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:\'Space\',bubbles:true}));return __test.bullets.some(b=>b.owner===t.id);}'
        );
        if ( truth_value( ( !truth_value($ok) ) ) ) {
            $ok = evaluate_js( $p,
'()=>{__test.setPhase(\'playing\');const t=__test.tanks.find(t=>t.human&&t.id!==0);t.cooldown=0;window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:\'Space\',bubbles:true}));__test.humanControl(t,1/120);window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:\'Space\',bubbles:true}));__test.setPhase(\'paused\');return __test.bullets.some(b=>b.owner===t.id);}'
            );
        }
        main::check( $ok, ( 'Space fires secondary seat seven ' . format_value($size) ) );
        main::snap( $p, ( 'playing-' . format_value( $size->[0] ) ) );
        main::check( ( ( evaluate_js( $p->locator('#arena'), '(e)=>e.width' ) <= ( $size->[0] + 5 ) ) ),
            ( 'Performance DPR cap ' . format_value($size) ) );
        $p->close();
    }
    $p = main::load( undef, undef, undef, undef, $saved );
    main::check( $p->locator('#fpsIndicator')->isVisible(), 'FPS choice restores on reload' );
    main::settings($p);
    main::check( $p->locator('#performanceMode')->isChecked(), 'Graphics preference restores' );
    main::closeControls($p);
    $p->close();
    $p = main::load();
    main::check(
        evaluate_js(
            $p,
'()=>{const full=__test.walls;let seed=35;const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const T=__test,world=leqra.getState().world;const original=T.rayWalls.toString();const brute=eval(\'(\'+original.replace(\'nearbyWalls(x,y,dx,dy,r)\',\'full\')+\')\');for(let i=0;i<2000;i++){let x=rnd()*world.width,y=rnd()*world.height,dx=(rnd()-.5)*world.width,dy=(rnd()-.5)*world.height,r=rnd()*20;if(i%2===0){dx*=.05;dy*=.05}const a=T.rayWalls(x,y,dx,dy,r),b=brute(x,y,dx,dy,r);if(JSON.stringify(a)!==JSON.stringify(b))return false;}return true}'
        ),
        'Indexed browser wall rays equal exhaustive reference'
    );
    main::check(
        evaluate_js(
            $p,
'source=>{const walls=__test.walls,clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),brute=eval(\'(\'+source+\')\');let seed=351;const rnd=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const world=leqra.getState().world;for(let i=0;i<4000;i++){let a={x:rnd()*world.width,y:rnd()*world.height,r:9+rnd()*15};if(i%2===0){const w=walls[Math.floor(rnd()*walls.length)];a.x=w.x+w.w*rnd();a.y=w.y+w.h*rnd();}const b={...a};__test.resolveWalls(a);brute(b);if(Math.abs(a.x-b.x)>1e-8||Math.abs(a.y-b.y)>1e-8)return false;}return true}',
            $root->child('tests/fixtures/resolve-wall-original35.js')->slurp_utf8
        ),
        'Indexed browser tank resolution matches original at 4000 positions'
    );
    $p->close();
    $host = main::load();
    $code = ( 'Eight & chat 💥 ' . format_value( int( time() * 1e9 ) ) );

    while ( truth_value( ( ( main::active($host) < 7 ) ) ) ) {
        $host->locator('#addBotBtn')->click();
    }
    main::rules( $host, { 'mode' => 'koth', 'timeLimit' => 600, 'scoreTarget' => 300 } );
    $host->locator('#localRoomName')->fill($code);
    $host->locator('#copyInviteBtn')->click();
    main::conn($host);
    $guest = main::load( 'GUEST', undef, $code, undef, undef );
    main::conn($guest);
    wait_js( $guest, 'leqra.getState().room.players.length===8' );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( main::state($guest)->{'online'}->{'spectating'} ) );
                truth_value($boolean_value)
                  ? ( value_eq( main::state($guest)->{'online'}->{'id'}, 7 ) )
                  : $boolean_value;
            }
        ),
        'Eighth online player gets final tank'
    );
    $viewer = main::load( 'OVERFLOW', [ 320, 568 ], $code, undef, undef );
    main::conn($viewer);
    main::check( main::state($viewer)->{'online'}->{'spectating'}, 'Ninth normal join becomes spectator' );
    $watch = main::load( 'WATCHER', [ 844, 390 ], $code, JSON::PP::true, undef );
    main::check( $watch->locator('#pilotName')->isVisible(), 'Watch link still requires callsign' );
    $watch->locator('#pilotName')->fill('WATCHER');
    $watch->locator('#joinRoomBtn')->click();
    main::conn($watch);

    for $p ( @{ [ $host, $guest, $viewer, $watch ] } ) {
        main::check(
            $p->locator('#chatBtn')->isVisible(),
            (
                (
                    ( 'Chat available to ' . main::state($p)->{'room'}->{'players'}->[0]->{'name'} )
                    . ' member '
                )
                . format_value( main::state($p)->{'online'}->{'id'} )
            )
        );
    }
    main::chat( $host, 'Hello everyone 💥' );
    main::message( $guest,  'Hello everyone 💥' );
    main::message( $viewer, 'Hello everyone 💥' );
    main::check( ( value_eq( $viewer->locator('#chatBadge')->innerText(), '1' ) ),
        'Unread count includes players for spectator' );
    main::chat( $viewer, '<img src=x onerror="window.injected=true">' );
    main::message( $host, '<img src=x onerror="window.injected=true">' );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( evaluate_js( $host, 'window.injected||false' ) ) );
                truth_value($boolean_value)
                  ? ( value_eq( $host->locator('#chatMessages img')->count(), 0 ) )
                  : $boolean_value;
            }
        ),
        'Untrusted chat stays literal text'
    );
    main::check( ( contains_value( $host->locator('#chatMessages')->innerText(), 'WATCHING' ) ),
        'Spectator role shown' );
    main::chat( $guest, 'Tank eight ready' );
    main::message( $watch, 'Tank eight ready' );
    main::check( ( contains_value( $watch->locator('#chatMessages')->innerText(), 'GUEST' ) ),
        'Player callsign attributed in chat' );
    for $p ( @{ [ $host, $guest, $viewer, $watch ] } ) {
        if ( truth_value( $p->locator('#chatPanel')->isVisible() ) ) {
            $p->locator('#chatCloseBtn')->click();
        }
    }
    $guest->locator('#readyBtn')->click();
    wait_js( $host, '!document.querySelector("#startRoomBtn").disabled' );
    main::start($host);
    wait_js( $viewer, 'leqra.getState().phase==="playing"' );
    main::check( ( value_eq( scalar( @{ main::state($viewer)->{'tanks'} } ), 8 ) ),
        'Spectator receives eight authoritative tanks' );
    $Leqra::Browser::HANDLE->await( $viewer->waitForTimeout(700) );
    $before = main::arena($viewer);
    main::chat( $viewer, 'Watching the live match' );
    main::message( $guest, 'Watching the live match' );
    main::check( ( value_eq( main::arena($viewer), $before ) ), 'Opening chat never resizes arena' );
    main::check( ( value_eq( main::state($viewer)->{'phase'}, 'playing' ) ),
        'Chat does not pause online game' );
    main::snap( $viewer, 'chat-320' );
    $watch->locator('#chatBtn')->click();
    main::snap( $watch, 'chat-844' );
    $host->locator('#chatBtn')->click();
    main::snap( $host, 'chat-desktop' );
    $n = evaluate_js( $host, '__sent.length' );
    $host->locator('#chatInput')->fill('');
    $host->locator('#chatInput')->press('f');
    $host->locator('#chatInput')->press('w');
    $Leqra::Browser::HANDLE->await( $host->waitForTimeout(100) );
    main::check(
        evaluate_js(
            $host, 'n=>__sent.slice(n).filter(m=>m.type==="input").every(m=>!m.fire&&!m.forward)', $n
        ),
        'Typing chat never fires/moves a tank'
    );
    $host->locator('#chatInput')->press('Escape');
    main::check( $host->locator('#chatPanel')->isHidden(), 'Escape closes chat without room menu' );
    $late = main::load( 'LATE', undef, $code, undef, undef );
    main::conn($late);
    main::message( $late, 'Watching the live match' );
    main::check( main::state($late)->{'online'}->{'spectating'}, 'History subscriber remains spectator' );
    $count = $late->locator('#chatMessages .chat-message')->count();
    evaluate_js( $late, '__sockets.at(-1).close()' );
    wait_js( $late, '__sockets.length>1&&leqra.getState().online.connected', undef, { timeout => 15000 } );
    main::message( $late, 'Watching the live match' );
    main::check( ( value_eq( $late->locator('#chatMessages .chat-message')->count(), $count ) ),
        'Reconnect history has no duplicates' );
    $elsewhere = main::load('ELSEWHERE');
    $elsewhere->locator('#localRoomName')->fill( ( 'Other ' . format_value( int( time() * 1e9 ) ) ) );
    $elsewhere->locator('#copyInviteBtn')->click();
    main::conn($elsewhere);
    main::chat( $host, 'Room-only message' );
    main::message( $guest, 'Room-only message' );
    $Leqra::Browser::HANDLE->await( $elsewhere->waitForTimeout(100) );
    main::check( ( value_eq( $elsewhere->locator('#chatMessages .chat-message')->count(), 0 ) ),
        'Chat isolated to its room' );
    $host->locator('#chatCloseBtn')->click();
    $host->locator('#roomBtn')->click();
    $host->locator('#returnRoomBtn')->click();
    wait_js( $host,  'leqra.getState().phase==="onlineLobby"' );
    wait_js( $guest, 'leqra.getState().phase==="onlineLobby"' );
    main::check( ( ( $host->locator('#chatMessages .chat-message')->count() >= 5 ) ),
        'Returning to room keeps chat history' );
    $guest->locator('#readyBtn')->click();
    wait_js( $host, '!document.querySelector("#startRoomBtn").disabled' );
    main::start($host);
    main::message( $viewer, 'Room-only message' );
    main::check( main::state($viewer)->{'online'}->{'spectating'},
        'New match keeps chatting spectator role' );
    main::check( ( !truth_value($errors) ), 'No browser runtime errors' );
    $report = {
        'version' => '3.6.0',
        'passed'  => scalar( @{$checks} ),
        'checks'  => $checks,
        'errors'  => $errors,
        'limits'  =>
'Chromium desktop/mobile emulation, exact assets injected with synthetic URL/storage, real loopback Go server. No physical devices/public internet.'
    };
    $out->child('report.json')->spew_utf8( json_text( $report, 1 ) );
    print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
    1;
};
if ($@) {
    $out->child('failure.json')
      ->spew_utf8( json_text( { 'passed' => $checks, 'errors' => $errors, 'traceback' => $@ }, 1 ) );
    for my $item ( @{ [ map { [ $_, $contexts->[$_] ] } 0 .. $#{$contexts} ] } ) {
        my $tuple_104_6 = $item;
        my $i           = $tuple_104_6->[0];
        my $c           = $tuple_104_6->[1];
        for my $p ( @{ $c->{'pages'} } ) {
            eval {
                $p->screenshot(
                    {
                        path => format_value( $out->child( ( ( 'failure-' . format_value($i) ) . '.png' ) ) )
                    }
                );
                1;
            };
            if ($@) {
            }
        }
    }
    die undef;
}
$browser->close();
