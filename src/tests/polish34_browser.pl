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
    $after,  $ap,     $args,     $base,      $before, $browser, $c,
    $checks, $code,   $contexts, $current,   $dead,   $errors,  $full,
    $go,     $guest,  $hit,      $host,      $i,      $index,   $measurements,
    $mode,   $name,   $nohit,    $oldweb,    $out,    $p,       $power,
    $pw,     $q,      $result,   $resurrect, $root,   $saved,   $size,
    $t,      $target, $two,      $v,         $victim, $viewer,  $web,
    $x,      $z
);

# v3.4: exact browser assets, local simulation and loopback Go snapshots.
# Uses Location/History/storage adapters; no shipped production debug endpoint.
$ap   = {};
$args = do {
    my %args = (
        'url'      => 'http://127.0.0.1:8878',
        'output'   => 'test-output/polish34',
        'browser'  => '/usr/bin/chromium',
        'baseline' => undef
    );
    my $help;
    GetOptions(
        'url=s'      => \$args{'url'},
        'output=s'   => \$args{'output'},
        'browser=s'  => \$args{'browser'},
        'baseline=s' => \$args{'baseline'},
        'help|h'     => \$help
      )
      or die 'Usage: perl polish34_browser.pl --url --output --browser --baseline
';
    if ($help) {
        print 'Usage: perl polish34_browser.pl --url --output --browser --baseline
';
        exit 0;
    }
    \%args;
};
$root = path($0)->absolute->parent(2);
$web  = $root->child('web');
$out  = path( $args->{'output'} );
$out->mkpath;
$checks       = [];
$errors       = [];
$measurements = [];

sub check {
    my ( $v, $label ) = @_;
    if ( truth_value( ( !truth_value($v) ) ) ) {
        die json_text($label);
    }
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub fixture {
    my ( $code, $action, $player ) = @_;
    my ($r);
    $player //= 0;
    $r = request_ok(
        HTTP::Request->new(
            'POST',
            ( $args->{'url'} . '/_fixture/features32' ),
            [ %{ { 'Content-Type' => 'application/json' } } ],
            Encode::encode_utf8(
                json_text(
                    {
                        'code'   => $code,
                        'action' => $action,
                        'player' => $player
                    }
                )
            )
        )
    );
    return decode_json( $r->content );
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
    executablePath => $args->{'browser'}
);
$contexts = [];

sub load {
    my ( $name, $size, $code, $watch, $storage, $source ) = @_;
    my ( $assets, $context, $html, $i, $js, $mobile, $p, $url, $w );
    $name    //= 'HOST';
    $size    //= [ 1365, 950 ];
    $code    //= undef;
    $watch   //= JSON::PP::false;
    $storage //= undef;
    $source  //= undef;
    $mobile = (
        do {
            my $boolean_value = ( ( $size->[0] < 760 ) );
            truth_value($boolean_value)
              ? $boolean_value
              : ( ( $size->[1] < 620 ) );
        }
    );
    $context = $browser->newContext(
        {
            viewport          => { 'width' => $size->[0], 'height' => $size->[1] },
            isMobile          => $mobile,
            hasTouch          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 )
        }
    );
    push( @{$contexts}, $context );
    $p = $context->newPage();
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->on( 'dialog', 'arguments[0].accept();' );
    $w = (
        do {
            my $boolean_value = $source;
            truth_value($boolean_value) ? $boolean_value : $web;
        }
    );
    $assets = asset_directory($w);
    $html   = replace_re( '<link[^>]*>',                         '', $w->child('index.html')->slurp_utf8 );
    $html   = replace_re( '<script src="[^"]+" defer></script>', '', $html );
    $html   = replace_text( $html, '</head>',
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
'([url,ws,name,storage])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied=\'\';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({\'leqra.name\':name,\'leqra.muted\':\'1\'},storage||{});Object.defineProperty(window,\'localStorage\',{value:store(__store)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});}',
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

sub closewin {
    my ($p) = @_;
    if (
        truth_value(
            (
                do {
                    my $boolean_value = $p->locator('#victoryDialog')->count();
                    truth_value($boolean_value)
                      ? $p->locator('#victoryDialog')->isVisible()
                      : $boolean_value;
                }
            )
        )
      )
    {
        $p->locator('#victoryCloseBtn')->click();
    }
}

sub preset {
    my ( $p, $index ) = @_;
    main::closewin($p);
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetSelect')->selectOption( ( 'builtin:' . format_value($index) ) );
    $p->locator('#loadPresetBtn')->click();
    wait_js( $p, '!document.querySelector("#presetsDialog").open' );
}

sub start {
    my ($p) = @_;
    main::closewin($p);
    $p->locator('#startRoomBtn')->click();
    wait_js( $p, 'leqra.getState().phase==="playing"', undef, { timeout => 9000 } );
}

sub room {
    my ($p) = @_;
    main::closewin($p);
    if ( truth_value( ( value_eq( main::state($p)->{'mode'}, 'room' ) ) ) ) {
        evaluate_js( $p, '__test.returnToRoom()' );
        return undef;
    }
    $p->locator('#roomBtn')->click();
    $p->locator('#returnRoomBtn')->click();
    wait_js( $p, '["menu","onlineLobby"].includes(leqra.getState().phase)' );
}

sub rules {
    my ( $p, $values ) = @_;
    my ( $control, $k, $n, $selected_mode, $selector, $setting, $v, $value );
    $values //= {};
    main::closewin($p);
    $selected_mode = splice( @{$values}, 'mode', 1 );
    if ( truth_value( ( defined($selected_mode) ) ) ) {
        $p->locator( ( ( '[data-room-mode="' . $selected_mode ) . '"]' ) )->click();
        wait_js( $p, '(mode)=>leqra.getState().rules.mode===mode', $selected_mode, {} );
    }
    for my $item ( @{ [ [ 'teamMode', '#roomTeamMode' ], [ 'mapSize', '#roomMapSize' ] ] } ) {
        my $tuple_43_6 = $item;
        my $setting    = $tuple_43_6->[0];
        my $selector   = $tuple_43_6->[1];
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
        my $tuple_50_6 = $item;
        my $k          = $tuple_50_6->[0];
        my $v          = $tuple_50_6->[1];
        my $n          = $p->locator( ( '#rule-' . $k ) );
        if ( truth_value( ( value_eq( $k, 'friendlyFire' ) ) ) ) {
            $n->setChecked($v);
        }
        else {
            if ( truth_value( ( contains_value( [ 'teamMode', 'mapSize', 'pickupRate' ], $k ) ) ) ) {
                if ( truth_value( $n->isDisabled() ) ) {
                    assert_ok( ( value_eq( $n->inputValue(), format_value($v) ) ),
                        'n.input_value()==str(v)' );
                }
                else {
                    $n->selectOption( format_value($v) );
                }
            }
            else {
                $n->fill( format_value($v) );
            }
        }
    }
    $p->locator('#applyRulesBtn')->click();
    wait_js( $p, '!document.querySelector("#rulesDialog").open' );
}

sub box {
    my ($p) = @_;
    return evaluate_js( $p,
'()=>{const r=document.querySelector(\'#arenaWrap\').getBoundingClientRect(),u=document.querySelector(\'.underbar\').getBoundingClientRect();return {width:r.width,height:r.height,x:r.x,y:r.y,hud:u.height,canvasW:document.querySelector(\'#arena\').width,canvasH:document.querySelector(\'#arena\').height};}'
    );
}

sub freeze {
    my ($p) = @_;
    evaluate_js( $p,
'()=>{__test.setPhase(\'paused\');__test.clearBullets();for(const t of __test.tanks){t.power=null;t.powerTime=0;t.speedTime=0;t.shield=0;t.alive=true;t.invulnerable=0;}__test.updateHUD(true);}'
    );
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
}
eval {
    if ( truth_value( $args->{'baseline'} ) ) {
        $target = $out->child('baseline');
        $target->mkpath;
        $z = open_archive( $args->{'baseline'} );
        for $name ( @{ [ $z->memberNames ] } ) {
            if ( truth_value( ( contains_value( $name, '/web/' ) ) ) ) {
                extract_archive_member( $z, $name, $target );
            }
        }
        $oldweb = $target->child('leqra-online/web');
        $p      = main::load( undef, [ 390, 844 ], undef, undef, undef, $oldweb );
        main::start($p);
        main::freeze($p);
        $before = main::box($p);
        evaluate_js( $p, '__test.grantPower(__test.tanks[0],\'speed\');__test.updateHUD(true)' );
        $Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
        $after = main::box($p);
        push(
            @{$measurements},
            {
                'baseline' => 'v3.3 buff HUD',
                'before'   => $before,
                'after'    => $after
            }
        );
        main::check(
            ( !value_eq( $before->{'height'}, $after->{'height'} ) ),
            'Reproduced v3.3 power-up-triggered arena resize'
        );
        $resurrect = evaluate_js( $p,
'()=>{const T=__test,o=T.online,now=performance.now();const s={generation:1,tick:100,phaseTime:0,roundClock:60,received:now+12,tanks:[],bullets:[],pickups:[],tankMap:new Map(),bulletMap:new Map()};o.buffer=new leqraNet.SnapshotBuffer();o.buffer.push(s,now);o.snapshots=o.buffer.items;o.trails=new Map();T.setPhase(\'playing\');T.renderOnlineMotion(.016,now);T.updateHUD(true);return !document.querySelector(\'#announcer\').hidden&&document.querySelector(\'#announceMain\').textContent===\'GO\'}'
        );
        main::check( $resurrect, 'Reproduced v3.3 stale GO from RAF timestamp preceding snapshot receipt' );
        $p->close();
    }
    for $size ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        for $two ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
            $p = main::load( undef, $size, undef, undef, undef, undef );
            if ( truth_value($two) ) {
                $p->locator('#addLocalBtn')->click();
            }
            main::start($p);
            main::freeze($p);
            $base = main::box($p);
            for $power ( @{ [ 'speed', 'shield', 'scatter', 'rapid', 'homing', 'laser', 'grenade' ] } ) {
                evaluate_js(
                    $p,
'power=>{for(const t of __test.tanks){if(t.human)__test.grantPower(t,power)};__test.updateHUD(true);}',
                    $power
                );
                $Leqra::Browser::HANDLE->await( $p->waitForTimeout(45) );
                $current = main::box($p);
                main::check(
                    ( value_eq( $current, $base ) ),
                    (
                            $size . ' '
                          . ( 1 + $two )
                          . ' pilots: '
                          . $power
                          . ' does not change arena/HUD geometry'
                    )
                );
            }
            evaluate_js( $p,
'()=>{for(const t of __test.tanks){t.power=null;t.speedTime=0;t.shield=0;t.alive=false;}__test.updateHUD(true)}'
            );
            $Leqra::Browser::HANDLE->await( $p->waitForTimeout(50) );
            main::check( ( value_eq( main::box($p), $base ) ),
                ( $size . ' ' . ( 1 + $two ) . ' pilots: expiry/death keeps arena stable' ) );
            main::check( evaluate_js( $p, 'document.documentElement.scrollWidth<=innerWidth' ),
                ( ( ( 'No horizontal page overflow ' . format_value($size) ) . ' ' ) . format_value($two) ) );
            $p->screenshot(
                {
                    path => format_value(
                        $out->child( ( 'hud-' . $size->[0] . 'x' . $size->[1] . '-' . $two . '.png' ) )
                    )
                }
            );
            $p->close();
        }
    }
    $p = main::load();
    main::preset( $p, 2 );
    main::start($p);
    main::freeze($p);
    $result = evaluate_js( $p,
'()=>{const T=__test;let result=[];for(const t of T.tanks){t.team=2;t.alive=true;t.shield=0;t.invulnerable=0;T.hurt(t,{owner:t.id});result.push(!t.alive);}return result}'
    );
    main::check( ( !grep { !$_ } @{$result} ),
        'All local tank slots die from their own shots with friendly fire off' );
    main::room($p);
    main::rules( $p, { 'friendlyFire' => JSON::PP::true } );
    main::check( ( value_eq( main::state($p)->{'rules'}->{'friendlyFire'}, JSON::PP::true ) ),
        'Host enables friendly fire in local rules' );
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetName')->fill('Friendly fire test');
    $p->locator('#savePresetBtn')->click();
    main::check(
        decode_json( evaluate_js( $p, '__store["leqra.presets.v1"]' ) )->{'items'}->[0]->{'rules'}
          ->{'friendlyFire'},
        'Saved preset retains friendly-fire setting'
    );
    $p->locator('[data-close-dialog="presetsDialog"]')->click();
    main::start($p);
    main::freeze($p);
    $hit = evaluate_js( $p,
'()=>{const T=__test,[a,b]=T.tanks;for(const t of [a,b])Object.assign(t,{team:2,alive:true,shield:0,invulnerable:0});T.hurt(b,{owner:a.id});return !b.alive}'
    );
    main::check( $hit, 'Enabled friendly fire harms local teammate' );
    main::room($p);
    main::rules( $p, { 'friendlyFire' => JSON::PP::false } );
    main::start($p);
    main::freeze($p);
    $nohit = evaluate_js( $p,
'()=>{const T=__test,[a,b]=T.tanks;for(const t of [a,b])Object.assign(t,{team:2,alive:true,shield:5,invulnerable:0});T.hurt(b,{owner:a.id});return b.alive&&b.shield===5}'
    );
    main::check( $nohit, 'Disabled friendly fire protects teammate and their shield' );
    main::room($p);
    $before = main::box($p);
    $p->locator('#sidebarBtn')->click();
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
    $after = main::box($p);
    main::check(
        (
            do {
                my $boolean_value = $p->locator('.sidebar')->isHidden();
                truth_value($boolean_value)
                  ? ( ( $after->{'width'} > ( $before->{'width'} + 180 ) ) )
                  : $boolean_value;
            }
        ),
        'Hiding sidebar releases horizontal arena space'
    );
    main::check( ( value_eq( $p->locator('#sidebarBtn')->getAttribute('aria-expanded'), 'false' ) ),
        'Sidebar toggle exposes accessible state' );
    $saved = evaluate_js( $p, '({...__store})' );
    $q     = main::load( undef, undef, undef, undef, $saved, undef );
    main::check( $q->locator('.sidebar')->isHidden(), 'Sidebar preference survives reload through storage' );
    $q->close();
    $p->locator('#fullscreenBtn')->click();
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(180) );
    $full = evaluate_js( $p, '!!document.fullscreenElement' );
    main::check( $full, 'Native fullscreen entered successfully in Chromium' );
    main::check(
        (
            do {
                my $boolean_value = $p->locator('.hero')->isHidden();
                truth_value($boolean_value)
                  ? $p->locator('.footer')->isHidden()
                  : $boolean_value;
            }
        ),
        'Fullscreen removes page chrome'
    );
    main::check( ( ( main::box($p)->{'width'} >= ( $p->viewportSize()->{'width'} - 32 ) ) ),
        'Fullscreen hidden-sidebar arena spans viewport' );
    $p->screenshot( { path => format_value( $out->child('fullscreen-expanded.png') ) } );
    $p->locator('#fullscreenBtn')->click();
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(120) );
    $p->locator('#sidebarBtn')->click();
    main::check( $p->locator('.sidebar')->isVisible(), 'Sidebar can be restored' );
    $p->close();
    for my $item ( @{ [ [ 'ctf', 3 ], [ 'koth', 4 ] ] } ) {
        my $tuple_106_6 = $item;
        my $mode        = $tuple_106_6->[0];
        my $index       = $tuple_106_6->[1];
        my $p           = main::load( undef, [ 390, 844 ], undef, undef, undef, undef );
        main::preset( $p, $index );
        main::start($p);
        main::freeze($p);
        if ( truth_value( ( value_eq( $mode, 'ctf' ) ) ) ) {
            $p->screenshot( { path => format_value( $out->child('flag-home-phone.png') ) } );
            evaluate_js( $p,
'()=>{const f=__test.localObjectives.flags[1],t=__test.tanks[0];f.carrier=t.id;f.home=false;f.x=t.x;f.y=t.y;}'
            );
            $Leqra::Browser::HANDLE->await( $p->waitForTimeout(60) );
            $p->screenshot(
                {
                    path => format_value( $out->child('flag-carried-phone.png') )
                }
            );
        }
        my $result = evaluate_js( $p,
'()=>{const T=__test;T.setPhase(\'playing\');T.setClock(0);T.tanks[0].alive=false;T.stepLocalObjectives(0);return {state:leqra.getState(),alive:T.tanks.every(t=>t.alive),generation:T.localObjectives.showdown}}'
        );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( value_eq( $result->{'state'}->{'phase'}, 'playing' ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value =
                          $result->{'state'}->{'objectives'}->{'suddenDeath'};
                        truth_value($boolean_value)
                          ? $result->{'alive'}
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( $mode . ' starts sudden death with all final lives' )
        );
        evaluate_js( $p, '__test.setPhase(\'paused\');__test.updateHUD(true)' );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( contains_value( $p->locator('#objectiveModeLabel')->innerText(), 'SUDDEN DEATH' ) );
                    truth_value($boolean_value)
                      ? $p->locator('#announcer')->isHidden()
                      : $boolean_value;
                }
            ),
            ( $mode . ' persistent unobtrusive sudden-death banner; no GO' )
        );
        $p->screenshot(
            {
                path => format_value( $out->child( ( 'sudden-death-' . $mode . '.png' ) ) )
            }
        );
        my $dead = evaluate_js( $p,
'()=>{const T=__test,t=T.tanks[0];t.invulnerable=0;T.hurt(t,{owner:t.id});T.respawnLocalPlayers(50);T.updateHUD(true);return{alive:t.alive,caption:document.querySelector(\'#cooldownText1\').textContent}}'
        );
        main::check(
            (
                do {
                    my $boolean_value = ( !truth_value( $dead->{'alive'} ) );
                    truth_value($boolean_value)
                      ? ( !truth_value( ( index( $dead->{'caption'}, 'RESPAWN' ) == 0 ) ) )
                      : $boolean_value;
                }
            ),
            ( $mode . ' no resurrection or misleading respawn countdown' )
        );
        evaluate_js( $p,
'()=>{const T=__test;T.setPhase(\'playing\');const winner=T.tanks[1];for(const t of T.tanks)t.alive=t.id===winner.id;T.stepLocalSuddenDeath();}'
        );
        main::check(
            (
                do {
                    my $boolean_value = $p->locator('#victoryDialog')->isVisible();
                    truth_value($boolean_value)
                      ? ( contains_value( $p->locator('#victoryTitle')->innerText(), 'WINS!' ) )
                      : $boolean_value;
                }
            ),
            ( $mode . ' surviving side receives victory popup' )
        );
        main::check( ( contains_value( $p->locator('#victoryMessage')->innerText(), 'sudden death' ) ),
            ( $mode . ' popup explains survival winner' ) );
        $p->screenshot(
            {
                path => format_value( $out->child( ( 'victory-' . $mode . '.png' ) ) )
            }
        );
        main::closewin($p);
        main::check( $p->locator('#roomScreen')->isVisible(), 'Closing victory returns to same room' );
        $p->close();
    }
    $host = main::load('CAPTAIN');
    main::preset( $host, 2 );
    $victim = (
        [
            map {
                my $v = $_;
                truth_value( ( value_eq( $v->{'kind'}, 'bot' ) ) ) ? ($v) : ()
            } @{ main::state($host)->{'room'}->{'players'} }
        ]->[0] // undef
    );
    $host->locator( ( '#roomRoster [data-kick-target="' . $victim->{'id'} . '"]' ) )->click();
    $host->locator('#confirmKickBtn')->click();
    main::rules(
        $host,
        {
            'mode'         => 'ctf',
            'scoreTarget'  => 3,
            'friendlyFire' => JSON::PP::true,
            'pickupRate'   => 'off'
        }
    );
    $code = ( 'Polish v34 ' . format_value( time() ) );
    $host->locator('#localRoomName')->fill($code);
    $host->locator('#copyInviteBtn')->click();
    wait_js( $host, 'leqra.getState().online?.connected' );
    $guest = main::load( 'FRIEND', undef, $code, undef, undef, undef );
    wait_js( $guest, 'leqra.getState().online?.connected' );
    wait_js( $host,  'leqra.getState().room.players.length===4' );
    $viewer = main::load( 'OBSERVER', [ 320, 568 ], $code, JSON::PP::true, undef, undef );
    main::check(
        ( !truth_value( main::state($viewer)->{'online'} ) ),
        'Watch link still asks for callsign before joining'
    );
    $viewer->locator('#pilotName')->fill('OBSERVER');
    $viewer->locator('#joinRoomBtn')->click();
    wait_js( $viewer, 'leqra.getState().online?.spectating' );
    $guest->locator('#roomRulesBtn')->click();
    main::check(
        (
            do {
                my $boolean_value = $guest->locator('#rule-friendlyFire')->isDisabled();
                truth_value($boolean_value)
                  ? $guest->locator('#rule-friendlyFire')->isChecked()
                  : $boolean_value;
            }
        ),
        'Guest sees friendly-fire rule but cannot change it'
    );
    $guest->locator('[data-close-dialog="rulesDialog"]')->click();
    evaluate_js( $guest,
'()=>{const r={...leqra.getState().rules,friendlyFire:false};__sockets.at(-1).send(JSON.stringify({type:\'rules\',rules:r}))}'
    );
    wait_js( $guest, '__messages.some(m=>m.type==="error"&&m.code==="not_host")' );
    main::check( main::state($host)->{'rules'}->{'friendlyFire'},
        'Server rejects guest-forged friendly-fire change' );
    $guest->locator('#readyBtn')->click();
    wait_js( $host, 'leqra.getState().room.canStart' );
    main::start($host);
    wait_js( $viewer, 'leqra.getState().phase==="playing"' );
    $Leqra::Browser::HANDLE->await( $host->waitForTimeout(700) );
    $go = evaluate_js( $host,
'()=>{const T=__test,o=T.online,s=o.snapshots.at(-1);s.phaseTime=0;const saved=s.received;s.received=performance.now()+12;T.renderOnlineMotion(.016,performance.now());T.updateHUD();const r={visible:!document.querySelector(\'#announcer\').hidden,text:document.querySelector(\'#announceMain\').textContent};s.received=saved;return r;}'
    );
    main::check(
        (
            !truth_value(
                (
                    do {
                        my $boolean_value = $go->{'visible'};
                        truth_value($boolean_value)
                          ? ( value_eq( $go->{'text'}, 'GO' ) )
                          : $boolean_value;
                    }
                )
            )
        ),
        'Early RAF timestamp cannot resurrect GO banner'
    );
    main::fixture( $code, 'kill', 0 );
    $Leqra::Browser::HANDLE->await( $host->waitForTimeout(180) );
    main::check( $host->locator('#announcer')->isHidden(), 'A CTF death does not retrigger GO' );
    main::fixture( $code, 'warning', 0 );
    $Leqra::Browser::HANDLE->await( $host->waitForTimeout(100) );
    main::check( $host->locator('#announcer')->isHidden(), 'Missile proximity does not retrigger GO' );
    main::fixture( $code, 'tie34' );
    wait_js( $host,   'leqra.getState().objectives?.suddenDeath' );
    wait_js( $guest,  'leqra.getState().objectives?.suddenDeath' );
    wait_js( $viewer, 'leqra.getState().objectives?.suddenDeath' );
    main::check(
        !scalar(
            grep {
                my $x = $_;
                !( ( value_eq( main::state($x)->{'phase'}, 'playing' ) ) )
            } @{ [ $host, $guest, $viewer ] }
        ),
        'Online tied timer starts same sudden death for players and spectators'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  main::state($viewer)->{'online'}->{'spectating'};
                truth_value($boolean_value)
                  ? !
                  scalar( grep { my $t = $_; !( ( ( $t->{'id'} < 4 ) ) ) }
                      @{ main::state($viewer)->{'tanks'} } )
                  : $boolean_value;
            }
        ),
        'Spectator remains outside final-life lineup'
    );
    $viewer->screenshot( { path => format_value( $out->child('spectator-sudden-death.png') ) } );
    main::fixture( $code, 'finish34', 0 );
    wait_js( $host,   'document.querySelector("#victoryDialog").open' );
    wait_js( $guest,  'document.querySelector("#victoryDialog").open' );
    wait_js( $viewer, 'document.querySelector("#victoryDialog").open' );
    main::check(
        !scalar(
            grep {
                my $x = $_;
                !( ( value_eq( 'TEAM 1 WINS!', uc( $x->locator('#victoryTitle')->innerText() ) ) ) )
            } @{ [ $host, $guest, $viewer ] }
        ),
        'Host, guest and spectator congratulate the same winning team'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( contains_value( $viewer->locator('#victoryMembers')->innerText(), 'CAPTAIN' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $viewer->locator('#victoryMembers')->innerText(), 'PLAYER 2' ) )
                  : $boolean_value;
            }
        ),
        'Victory popup identifies winning team members'
    );
    $host->screenshot( { path => format_value( $out->child('online-victory.png') ) } );
    main::closewin($viewer);
    $Leqra::Browser::HANDLE->await( $viewer->waitForTimeout(300) );
    main::check( $viewer->locator('#victoryDialog')->isHidden(),
        'Repeated match-over snapshots do not reopen dismissed popup' );
    main::check( main::state($viewer)->{'online'}->{'spectating'},
        'Dismissing victory preserves spectator role' );
    main::closewin($host);
    main::closewin($guest);
    $guest->locator('#readyBtn')->click();
    wait_js( $host, 'leqra.getState().room.canStart' );
    main::start($host);
    wait_js( $viewer, 'leqra.getState().phase==="playing"' );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( main::state($viewer)->{'objectives'}->{'suddenDeath'} ) );
                truth_value($boolean_value)
                  ? main::state($viewer)->{'online'}->{'spectating'}
                  : $boolean_value;
            }
        ),
        'Rematch resets sudden death but retains spectators'
    );
    for $x ( @{ [ $host, $guest, $viewer ] } ) {
        $x->close();
    }
    main::check( ( !truth_value($errors) ), 'No browser JavaScript errors' );
    $out->child('results.json')->spew_utf8(
        json_text(
            {
                'passed'       => scalar( @{$checks} ),
                'checks'       => $checks,
                'measurements' => $measurements,
                'errors'       => $errors
            },
            1
        )
    );
    print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
    1;
};
if ($@) {
    for my $item ( @{ [ map { [ $_, $contexts->[$_] ] } 0 .. $#{$contexts} ] } ) {
        my $tuple_152_6 = $item;
        my $i           = $tuple_152_6->[0];
        my $c           = $tuple_152_6->[1];
        for my $p ( @{ $c->{'pages'} } ) {
            eval {
                $p->screenshot(
                    {
                        path => format_value( $out->child( ( 'failure-' . $i . '.png' ) ) )
                    }
                );
                1;
            };
            if ($@) {
            }
        }
    }
    $out->child('failure.json')->spew_utf8(
        json_text(
            {
                'passed'       => scalar( @{$checks} ),
                'checks'       => $checks,
                'errors'       => $errors,
                'measurements' => $measurements
            },
            1
        )
    );
    die undef;
}
$browser->close();
