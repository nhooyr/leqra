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
    $after,  $ap,     $args,  $assets,   $b,     $before, $browser, $c,     $cap,
    $case,   $checks, $code,  $contexts, $enemy, $errors, $fb,      $gen,   $got,
    $guest,  $lid,    $local, $out,      $p,     $phone,  $points,  $power, $pw,
    $report, $root,   $sb,    $size,     $ss,    $t,      $web,     $x
);

# v3.1 controls, HUD, and grenade impacts; exact-asset Chromium integration against opt-in loopback Go fixture.
# No production test endpoints. Navigation/History are adapters in this environment.
# Run LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790 go test -run '^TestBrowserFixture$' -timeout 30m
$ap   = {};
$args = do {
    my %args = (
        'url'     => 'http://127.0.0.1:18790',
        'browser' => '/usr/bin/chromium',
        'output'  => 'test-output/unified-room'
    );
    my $help;
    GetOptions(
        'url=s'     => \$args{'url'},
        'browser=s' => \$args{'browser'},
        'output=s'  => \$args{'output'},
        'help|h'    => \$help
      )
      or die 'Usage: perl gameplay31_browser.pl --url --browser --output
';
    if ($help) {
        print 'Usage: perl gameplay31_browser.pl --url --browser --output
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

sub fixture {
    my ( $code, $path, $extra ) = @_;
    my ($r);
    $path  //= 'lane';
    $extra //= {};
    $r = request_ok(
        HTTP::Request->new(
            'POST',
            ( ( $args->{'url'} . '/_fixture/' ) . $path ),
            [ %{ { 'Content-Type' => 'application/json' } } ],
            Encode::encode_utf8( json_text( { 'code' => $code } ) )
        )
    );
    return decode_json( $r->content );
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
    my ( $name, $code, $size, $session, $delay ) = @_;
    my ( $ctx, $html, $i, $js, $mobile, $p, $url );
    $name    //= 'PILOT';
    $code    //= undef;
    $size    //= [ 1365, 950 ];
    $session //= undef;
    $delay   //= 0;
    $mobile = (
        do {
            my $boolean_value = ( ( $size->[0] < 760 ) );
            truth_value($boolean_value)
              ? $boolean_value
              : ( ( $size->[1] < 620 ) );
        }
    );
    $ctx = $browser->newContext(
        {
            viewport          => { 'width' => $size->[0], 'height' => $size->[1] },
            isMobile          => $mobile,
            hasTouch          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 )
        }
    );
    push( @{$contexts}, $ctx );
    $p = $ctx->newPage();
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->on( 'dialog', 'arguments[0].accept();' );
    $html = replace_text(
        replace_text(
            replace_text(
                replace_re( '<link[^>]*>', '', $web->child('index.html')->slurp_utf8 ),
                '<script src="game.js" defer></script>', ''
            ),
            '<script src="netcode.js" defer></script>',
            ''
        ),
        '</head>',
        ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' )
    );
    $p->setContent($html);
    $url = (
        'http://game.test/tanks/?test=1'
          . (
            truth_value( ( defined($code) ) )
            ? ( '&' . query_string( { 'room' => $code } ) )
            : ''
          )
    );
    evaluate_js(
        $p, '([url,ws,name,session,delay])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied=\'\';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;
   window.WebSocket=class extends RealSocket{
    constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)));}
    send(v){__sent.push(JSON.parse(v));return super.send(v)}
   };
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':name,\'leqra.muted\':\'1\'})});
   Object.defineProperty(window,\'sessionStorage\',{value:store(session?{\'leqra.session\':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});
  }',
        [ $url, ( replace_text( $args->{'url'}, 'http:', 'ws:' ) . '/ws' ), $name, $session, $delay ]
    );
    $js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
    $i  = rindex( $js, '})()' );
    $js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location);' ) . substr( $js, ( $i + 4 ) ) );
    $p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.leqra' );
    return $p;
}

sub remove {
    my ( $p, $id ) = @_;
    $p->locator( ( '#roomRoster [data-kick-target="' . $id . '"]' ) )->click();
    $p->locator('#confirmKickBtn')->click();
    wait_js( $p, 'id=>!leqra.getState().room.players.some(p=>p.id===id)', $id, {} );
}

sub waitplayers {
    my ( $p, $n ) = @_;
    wait_js( $p, 'n=>leqra.getState().room.players.length===n', $n, {} );
}

sub press {
    my ( $p, $key, $ms ) = @_;
    $ms //= 80;
    $p->keyboard()->down($key);
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout($ms) );
    $p->keyboard()->up($key);
}

sub connected {
    my ($p) = @_;
    wait_js( $p, 'leqra.getState().online?.connected', undef, { timeout => 12000 } );
}

sub latest {
    my ($p) = @_;
    return evaluate_js( $p, '__messages.filter(m=>m.type==="state").at(-1)' );
}

sub menu {
    my ($p) = @_;
    $p->locator('#roomBtn')->click();
}

sub ready {
    my ($p) = @_;
    $p->locator('#readyBtn')->click();
}

sub room {
    my ($p) = @_;
    main::menu($p);
    $p->locator('#returnRoomBtn')->click();
    wait_js( $p, '["menu","onlineLobby"].includes(leqra.getState().phase)' );
}

sub team {
    my ( $p, $id, $n ) = @_;
    $p->locator( ( '#roomRoster [data-team="' . $id . '"]' ) )->selectOption( format_value($n) );
    wait_js( $p, '([id,n])=>leqra.getState().room.players.find(p=>p.id===id)?.team===n', [ $id, $n ], {} );
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(160) );
}

sub start {
    my ($p) = @_;
    $p->locator('#startRoomBtn')->click();
    wait_js( $p, 'leqra.getState().phase==="playing"', undef, { timeout => 8000 } );
}

sub local_lane {
    my ($p) = @_;
    evaluate_js( $p,
'()=>{const T=__test,w=leqra.getState().world;T.clearInput();T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.pickups.splice(0);T.tanks.forEach((t,i)=>Object.assign(t,{x:120,y:90+i*125,angle:0,invulnerable:100,cooldown:t.human?0:1000,power:null,powerTime:0,speedTime:0,charges:0,shield:0}));T.updateHUD(true);}'
    );
}

sub shells {
    my ( $p, $id ) = @_;
    return evaluate_js( $p, 'id=>__test.bullets.filter(b=>b.owner===id).length', $id );
}

sub save2 {
    my ( $p, $name, $prefix ) = @_;
    my ($form);
    $prefix //= 'room';
    $form = $p->locator( ( ( '#' . $prefix ) . 'P2CallsignForm' ) );
    $form->locator('input')->fill($name);
    $form->locator('button')->click();
    wait_js( $p, 'name=>leqra.getState().room.players.some(p=>p.kind==="local"&&p.name===name)', $name, {} );
}
$p = main::load('CAPTAIN');
main::check(
    (
        do {
            my $boolean_value = ( !truth_value( $p->locator('#roomP2CallsignForm')->isVisible() ) );
            truth_value($boolean_value)
              ? ( !truth_value( $p->locator('#pilotLoadout2')->isVisible() ) )
              : $boolean_value;
        }
    ),
    'Secondary name/HUD absent with only one local pilot'
);
main::start($p);
main::local_lane($p);
main::press( $p, 'KeyF', 45 );
main::check( ( value_eq( main::shells( $p, 0 ), 1 ) ),         'F fires primary tank in single-player room' );
main::check( evaluate_js( $p, '!document.fullscreenElement' ), 'F does not toggle fullscreen' );
main::local_lane($p);
main::press( $p, 'Space', 45 );
main::check( ( value_eq( main::shells( $p, 0 ), 1 ) ), 'Space remains fire alias with one local pilot' );
main::local_lane($p);
evaluate_js( $p, '()=>{const t=__test.tanks[0];__test.grantPower(t,\'grenade\');t.charges=1;}' );
$p->keyboard()->down('KeyF');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(60) );
main::check( ( value_eq( main::shells( $p, 0 ), 1 ) ), 'F throws one grenade' );
$p->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
main::check( ( value_eq( main::shells( $p, 0 ), 1 ) ),
    'Holding F then pressing Space is not a second logical Fire press' );
$p->keyboard()->up('KeyF');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(60) );
main::check( ( value_eq( main::shells( $p, 0 ), 1 ) ), 'Releasing F while Space is held does not detonate' );
$p->keyboard()->up('Space');
main::press( $p, 'KeyF', 40 );
main::check( ( value_eq( main::shells( $p, 0 ), 0 ) ),
    'Fresh Fire press after both aliases are released detonates' );
main::room($p);
$p->locator('#addLocalBtn')->click();
main::waitplayers( $p, 4 );
$lid = (
    [
        map {
            my $x = $_;
            truth_value( ( value_eq( $x->{'kind'}, 'local' ) ) )
              ? ( $x->{'id'} )
              : ()
        } @{ main::state($p)->{'room'}->{'players'} }
    ]->[0] // undef
);
main::check( ( value_eq( $lid, 3 ) ), 'Secondary player uses sparse slot 3, not assumed slot 1' );
main::check( $p->locator('#roomP2CallsignForm')->isVisible(),
    'Explicit Player 2 callsign editor appears on add' );
main::save2( $p, 'NOVA' );
main::check( ( value_eq( $p->locator('#roomP2CallsignStatus')->innerText(), 'Saved.' ) ),
    'Secondary local name save confirmed' );
main::check( ( value_eq( evaluate_js( $p, 'localStorage.getItem("leqra.local2Name")' ), 'NOVA' ) ),
    'Secondary name remembered on device' );
$p->locator('#roomP2Callsign')->fill('   ');
main::check( $p->locator('#roomP2CallsignForm button')->isDisabled(), 'Empty Player 2 name is not saveable' );
$p->locator('#roomP2Callsign')->fill('NOVA');
main::start($p);
main::local_lane($p);
main::check( $p->locator('#pilotLoadout2')->isVisible(), 'Secondary ammo panel appears in play' );
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#loadoutName2')->innerText(), 'NOVA' ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#loadoutKey1')->innerText(), 'F' ) )
              : $boolean_value;
        }
    ),
    'Both HUD identities and new P1 binding displayed'
);
main::press( $p, 'Space', 40 );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( main::shells( $p, 0 ), 0 ) );
            truth_value($boolean_value)
              ? ( value_eq( main::shells( $p, $lid ), 0 ) )
              : $boolean_value;
        }
    ),
    'Space does not fire either tank with two local pilots'
);
$p->keyboard()->down('KeyF');
$p->keyboard()->down('Enter');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(75) );
$p->keyboard()->up('KeyF');
$p->keyboard()->up('Enter');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( main::shells( $p, 0 ), 1 ) );
            truth_value($boolean_value)
              ? ( value_eq( main::shells( $p, $lid ), 1 ) )
              : $boolean_value;
        }
    ),
    'F and Enter fire independent local tanks simultaneously'
);
main::check(
    (
        do {
            my $boolean_value = ( value_eq( $p->locator('#ammoDots .ammo-dot.empty')->count(), 1 ) );
            truth_value($boolean_value)
              ? ( value_eq( $p->locator('#ammoDots2 .ammo-dot.empty')->count(), 1 ) )
              : $boolean_value;
        }
    ),
    'Both ammo counters reflect their own active bullets'
);
main::local_lane($p);
evaluate_js( $p, 'id=>{const t=__test.tanks.find(t=>t.id===id);__test.grantPower(t,"grenade");t.charges=1;}',
    $lid );
evaluate_js( $p,
'()=>{window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:\'Enter\',bubbles:true}));window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:\'Enter\',bubbles:true}));}'
);
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
main::check( ( value_eq( main::shells( $p, $lid ), 1 ) ),
    'Sub-tick Enter tap launches for secondary slot 3' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
main::check(
    ( contains_value( $p->locator('#weaponLabel2')->innerText(), 'DETONATE' ) ),
    'Secondary final-charge grenade keeps fuse/detonate display'
);
main::check( ( !( contains_value( $p->locator('#weaponLabel')->innerText(), 'DETONATE' ) ) ),
    'Secondary grenade does not change primary weapon label' );
main::press( $p, 'Enter', 45 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
main::check(
    (
        do {
            my $boolean_value = ( value_eq( main::shells( $p, $lid ), 0 ) );
            truth_value($boolean_value)
              ? ( !( contains_value( $p->locator('#weaponLabel2')->innerText(), 'DETONATE' ) ) )
              : $boolean_value;
        }
    ),
    'Secondary manual detonation clears its own fuse HUD'
);
main::menu($p);
$before = main::state($p);
main::save2( $p, 'STAR FOX', 'menu' );
$after = main::state($p);
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $before->{'scores'}, $after->{'scores'} ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value =
                  ( value_eq( $before->{'round'}, $after->{'round'} ) );
                truth_value($boolean_value)
                  ? ( value_eq( $before->{'tanks'}->[0]->{'x'}, $after->{'tanks'}->[0]->{'x'} ) )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'In-match local P2 rename does not restart round or reset scores'
);
main::check( ( value_eq( $p->locator('#loadoutName2')->innerText(), 'STAR FOX' ) ),
    'Renamed secondary appears in gameplay HUD' );
main::check( ( value_eq( $p->locator('#menuP2CallsignStatus')->innerText(), 'Saved.' ) ),
    'In-match name save confirmed' );
$p->locator('#returnRoomBtn')->click();
wait_js( $p, 'leqra.getState().phase==="menu"' );
main::remove( $p, $lid );
$p->locator('#addLocalBtn')->click();
main::check(
    (
        value_eq(
            (
                [
                    map {
                        my $x = $_;
                        truth_value( ( value_eq( $x->{'kind'}, 'local' ) ) )
                          ? ( $x->{'name'} )
                          : ()
                    } @{ main::state($p)->{'room'}->{'players'} }
                ]->[0] // undef
            ),
            'STAR FOX'
        )
    ),
    'Removing and re-adding secondary uses saved callsign'
);
main::remove( $p, 1 );
main::remove( $p, 2 );
$code = ( ( 'Impact HUD ' . format_value( int( time() ) ) ) . ' 💥' );
$p->locator('#localRoomName')->fill($code);
$p->locator('#copyInviteBtn')->click();
main::connected($p);
main::waitplayers( $p, 2 );
$lid = (
    [
        map {
            my $x = $_;
            truth_value( ( value_eq( $x->{'kind'}, 'local' ) ) )
              ? ( $x->{'id'} )
              : ()
        } @{ main::state($p)->{'room'}->{'players'} }
    ]->[0] // undef
);
$guest = main::load( 'GUEST', $code );
main::connected($guest);
main::waitplayers( $p, 3 );
main::check(
    ( !truth_value( $guest->locator('#roomP2CallsignForm')->isVisible() ) ),
    'Remote guest cannot edit a secondary pilot they do not control'
);
main::ready($guest);
wait_js( $p, '!document.querySelector("#startRoomBtn").disabled' );
main::save2( $p, 'ONLINE NOVA' );
wait_js( $guest, 'leqra.getState().room.players.some(p=>p.name==="ONLINE NOVA")' );
main::check(
    (
        [
            map {
                my $x = $_;
                truth_value( ( value_eq( $x->{'name'}, 'GUEST' ) ) )
                  ? ( $x->{'ready'} )
                  : ()
            } @{ main::state($p)->{'room'}->{'players'} }
        ]->[0] // undef
    ),
    'Secondary rename preserves guest readiness online'
);
main::start($p);
wait_js( $guest, 'leqra.getState().phase==="playing"' );
main::fixture( $code, 'powerups', { 'player' => 0, 'power' => 'rapid', 'missileScene' => 'range' } );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(200) );
main::press( $p, 'Space', 40 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
main::check( ( !truth_value( main::latest($p)->{'bullets'} ) ),
    'Server receives no Fire from Space with a secondary local tank' );
$p->keyboard()->down('KeyF');
$p->keyboard()->down('Enter');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
$p->keyboard()->up('KeyF');
$p->keyboard()->up('Enter');
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(180) );
main::check(
    (
        do {
            my $boolean_value =
              scalar( grep { my $b = $_; ( value_eq( $b->{'owner'}, 0 ) ) }
                  @{ main::latest($p)->{'bullets'} } );
            truth_value($boolean_value)
              ? scalar( grep { my $b = $_; ( value_eq( $b->{'owner'}, $lid ) ) }
                  @{ main::latest($p)->{'bullets'} } )
              : $boolean_value;
        }
    ),
    'Server receives both F and Enter controls independently'
);
main::check(
    (
        do {
            my $boolean_value =
              ( ( $p->locator('#ammoDots2 .ammo-dot.empty')->count() >= 1 ) );
            truth_value($boolean_value)
              ? ( !truth_value( $guest->locator('#pilotLoadout2')->isVisible() ) )
              : $boolean_value;
        }
    ),
    'Online controller sees P2 ammo; remote guest does not get an unrelated P2 HUD'
);
main::fixture(
    $code,
    'powerups',
    {
        'player'       => $lid,
        'power'        => 'grenade',
        'charges'      => 1,
        'missileScene' => 'range'
    }
);
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(200) );
main::press( $p, 'Enter', 40 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(130) );
main::check(
    ( contains_value( $p->locator('#weaponLabel2')->innerText(), 'DETONATE' ) ),
    'Server-backed secondary grenade displays armed HUD after final charge'
);
main::press( $p, 'Enter', 40 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(180) );
main::check(
    (
        !truth_value(
            scalar(
                grep {
                    my $b = $_;
                    (
                        do {
                            my $boolean_value =
                              ( value_eq( $b->{'owner'}, $lid ) );
                            truth_value($boolean_value)
                              ? ( value_eq( $b->{'kind'}, 'grenade' ) )
                              : $boolean_value;
                        }
                    )
                } @{ main::latest($p)->{'bullets'} }
            )
        )
    ),
    'Online P2 Enter remote detonation still works'
);
main::menu($p);
$before = main::state($p);
main::save2( $p, 'BATTLE NOVA', 'menu' );
wait_js( $guest, 'leqra.getState().room.players.some(p=>p.name==="BATTLE NOVA")' );
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $before->{'scores'}, main::state($p)->{'scores'} ) );
            truth_value($boolean_value)
              ? ( value_eq( $before->{'round'}, main::state($p)->{'round'} ) )
              : $boolean_value;
        }
    ),
    'Online in-match P2 rename preserves score and round'
);
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(150) );
main::fixture( $code, 'powerups',
    { 'player' => 0, 'power' => 'grenade', 'missileScene' => 'grenade-shield' } );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(200) );
main::press( $p, 'KeyF', 45 );
wait_js(
    $p,
'(()=>{const s=__messages.filter(m=>m.type==="state").at(-1);return s.events.some(e=>e.type==="blast"&&e.generation===s.generation)})()',
    undef,
    { timeout => 4000 }
);
$ss    = main::latest($p);
$enemy = (
    [
        map {
            my $t = $_;
            truth_value( ( value_eq( $t->{'id'}, 2 ) ) ) ? ($t) : ()
        } @{ $ss->{'tanks'} }
    ]->[0] // undef
);
main::check(
    (
        do {
            my $boolean_value = $enemy->{'alive'};
            truth_value($boolean_value)
              ? ( value_eq( $enemy->{'shield'}, 0 ) )
              : $boolean_value;
        }
    ),
    'Online grenade impact consumes one shield without a double-hit kill'
);
main::check( ( ( $ss->{'roundClock'} > 71 ) ), 'Online impact detonates before five-second fuse' );
main::fixture( $code, 'powerups',
    { 'player' => 0, 'power' => 'grenade', 'missileScene' => 'grenade-impact' } );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(200) );
$gen = main::latest($p)->{'generation'};
main::press( $p, 'KeyF', 45 );
wait_js( $p,
    'gen=>__messages.some(m=>m.type==="state"&&m.generation===gen&&m.tanks.some(t=>t.id===2&&!t.alive))',
    $gen, { timeout => 4000 } );
main::check( JSON::PP::true, 'Unshielded opposing tank is eliminated on online grenade impact' );
wait_js( $guest,
    'gen=>__messages.some(m=>m.type==="state"&&m.generation===gen&&m.events.some(e=>e.type==="blast"))',
    $gen, { timeout => 4000 } );
main::check( JSON::PP::true, 'Impact blast event reaches remote browser' );
$p->screenshot( { path => format_value( $out->child('online-impact.png') ) } );
$p->close();
$guest->close();
$local = main::load('PHYSICS');
main::start($local);
main::local_lane($local);

for $case ( @{ [ 'direct', 'shield', 'teammate', 'protected', 'wall', 'owner', 'stationary' ] } ) {
    $got = evaluate_js(
        $local,
'kind=>{const T=__test;T.setPhase(\'paused\');T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{alive:i<2,human:true,team:i+1,x:i?190:40,y:210,invulnerable:0,shield:kind===\'shield\'&&i===1?10:0}));const p=T.tanks[1];if(kind===\'teammate\')p.team=1;if(kind===\'protected\')p.invulnerable=10;const before=document.querySelector(\'#combatLog\').textContent;const b={kind:\'grenade\',owner:0,x:164,y:210,vx:205,vy:0,r:6,life:5,age:.3,dead:false,bounces:0,color:\'#ffc46b\',trail:[]};if(kind===\'wall\'){T.walls.push({x:170,y:0,w:8,h:600});b.x=155;}if(kind===\'owner\'){b.x=40;b.vx=0;}if(kind===\'stationary\'){b.x=180;b.vx=0;}T.addBullet(b);T.updateBullets(.1);if(kind===\'wall\')T.walls.pop();return{dead:b.dead,life:b.life,alive:p.alive,shield:p.shield,ownerAlive:T.tanks[0].alive,vx:b.vx}}',
        $case
    );
    if ( truth_value( ( value_eq( $case, 'wall' ) ) ) ) {
        main::check(
            (
                do {
                    my $boolean_value = ( !truth_value( $got->{'dead'} ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( ( $got->{'vx'} < 0 ) );
                        truth_value($boolean_value)
                          ? $got->{'alive'}
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            'Local grenade reflects from wall before tank contact'
        );
    }
    else {
        if ( truth_value( ( contains_value( [ 'teammate', 'protected' ], $case ) ) ) ) {
            main::check(
                (
                    do {
                        my $boolean_value = $got->{'dead'};
                        truth_value($boolean_value)
                          ? $got->{'alive'}
                          : $boolean_value;
                    }
                ),
                ( ( 'Local contact blast respects ' . $case ) . ' protection' )
            );
        }
        else {
            if ( truth_value( ( value_eq( $case, 'shield' ) ) ) ) {
                main::check(
                    (
                        do {
                            my $boolean_value = $got->{'dead'};
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value = $got->{'alive'};
                                truth_value($boolean_value)
                                  ? ( value_eq( $got->{'shield'}, 0 ) )
                                  : $boolean_value;
                              }
                              : $boolean_value;
                        }
                    ),
                    'Local impact shield absorbs exactly one blast'
                );
            }
            else {
                if ( truth_value( ( value_eq( $case, 'owner' ) ) ) ) {
                    main::check(
                        (
                            do {
                                my $boolean_value = $got->{'dead'};
                                truth_value($boolean_value)
                                  ? ( !truth_value( $got->{'ownerAlive'} ) )
                                  : $boolean_value;
                            }
                        ),
                        'Local own grenade triggers after launch grace'
                    );
                }
                else {
                    main::check(
                        (
                            do {
                                my $boolean_value = $got->{'dead'};
                                truth_value($boolean_value)
                                  ? do {
                                    my $boolean_value =
                                      ( !truth_value( $got->{'alive'} ) );
                                    truth_value($boolean_value)
                                      ? ( ( $got->{'life'} > 4.8 ) )
                                      : $boolean_value;
                                  }
                                  : $boolean_value;
                            }
                        ),
                        ( ( 'Local ' . $case ) . ' grenade impact before fuse' )
                    );
                }
            }
        }
    }
}
$local->close();
for $size ( @{ [ [ 1365, 950 ], [ 320, 568 ], [ 390, 844 ], [ 844, 390 ] ] } ) {
    $phone = main::load( 'CAPTAIN LONGNAME', undef, $size, undef, undef );
    $phone->locator('#addLocalBtn')->click();
    main::waitplayers( $phone, 4 );
    main::save2( $phone, 'SECOND LONGNAME' );
    $phone->locator('#roomP2Callsign')->scrollIntoViewIfNeeded();
    $phone->screenshot(
        {
            path => format_value( $out->child( ( 'room-' . $size->[0] . 'x' . $size->[1] . '.png' ) ) )
        }
    );
    main::check(
        evaluate_js( $phone, 'document.documentElement.scrollWidth<=innerWidth+1' ),
        ( 'Room naming has no horizontal overflow ' . format_value($size) )
    );
    main::start($phone);
    main::local_lane($phone);
    evaluate_js( $phone,
'()=>{const p=__test.tanks.find(t=>t.id===3);__test.grantPower(p,\'homing\');__test.grantPower(p,\'speed\');__test.grantPower(p,\'shield\');__test.grantPower(__test.tanks[0],\'scatter\');__test.updateHUD(true);}'
    );
    $Leqra::Browser::HANDLE->await( $phone->waitForTimeout(100) );
    main::check(
        (
            do {
                my $boolean_value =
                  ( contains_value( $phone->locator('#weaponLabel2')->innerText(), 'HOMING' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $phone->locator('#weaponLabel2')->innerText(), '×3' ) )
                  : $boolean_value;
            }
        ),
        ( 'Secondary weapon charges shown ' . format_value($size) )
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( contains_value( $phone->locator('#buffLabel2')->innerText(), 'SPEED' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $phone->locator('#buffLabel2')->innerText(), 'SHIELD' ) )
                  : $boolean_value;
            }
        ),
        ( 'Secondary independent buff timers shown ' . format_value($size) )
    );
    main::check(
        evaluate_js(
            $phone,
'()=>{const ids=[\'pilotLoadout1\',\'pilotLoadout2\',\'weaponLabel2\',\'buffLabel2\'];return ids.every(id=>{const b=document.getElementById(id).getBoundingClientRect();return b.left>=0&&b.right<=innerWidth+1&&b.top>=0&&b.bottom<=innerHeight+1})}'
        ),
        ( 'Both loadouts fit viewport ' . format_value($size) )
    );
    main::check(
        evaluate_js( $phone, 'document.documentElement.scrollWidth<=innerWidth+1' ),
        ( 'Playing HUD has no horizontal overflow ' . format_value($size) )
    );
    for my $item (
        @{ [ [ 'rapid', 9 ], [ 'scatter', 12 ], [ 'laser', 3 ], [ 'grenade', 3 ], [ 'homing', 3 ] ] } )
    {
        my $tuple_146_6 = $item;
        my $power       = $tuple_146_6->[0];
        my $cap         = $tuple_146_6->[1];
        evaluate_js( $phone,
            'power=>{__test.grantPower(__test.tanks.find(t=>t.id===3),power);__test.updateHUD(true)}',
            $power );
        main::check(
            ( value_eq( $phone->locator('#ammoDots2 .ammo-dot')->count(), $cap ) ),
            ( ( ( 'Secondary ' . $power ) . ' capacity ' ) . format_value($size) )
        );
    }
    evaluate_js( $phone,
        '()=>{__test.grantPower(__test.tanks.find(t=>t.id===3),\'homing\');__test.updateHUD(true)}' );
    $phone->screenshot(
        {
            path => format_value( $out->child( ( 'playing-' . $size->[0] . 'x' . $size->[1] . '.png' ) ) )
        }
    );
    if (
        truth_value(
            (
                do {
                    my $boolean_value = ( ( $size->[0] < 760 ) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( ( $size->[1] < 620 ) );
                }
            )
        )
      )
    {
        $c      = $phone->context()->newCDPSession($phone);
        $sb     = $phone->locator('#stickBase')->boundingBox();
        $fb     = $phone->locator('#fireBtn')->boundingBox();
        $points = [
            {
                'x'  => ( ( $sb->{'x'} + ( $sb->{'width'} / 2 ) ) + 26 ),
                'y'  => ( $sb->{'y'} + ( $sb->{'height'} / 2 ) ),
                'id' => 1
            },
            {
                'x'  => ( $fb->{'x'} + ( $fb->{'width'} / 2 ) ),
                'y'  => ( $fb->{'y'} + ( $fb->{'height'} / 2 ) ),
                'id' => 2
            }
        ];
        $c->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => $points } );
        $Leqra::Browser::HANDLE->await( $phone->waitForTimeout(150) );
        $c->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
        main::check( ( ( main::shells( $phone, 0 ) > 0 ) ),
            ( 'Paired HUD leaves touch steering/fire usable ' . format_value($size) ) );
    }
    $phone->close();
}
main::check( ( !truth_value($errors) ), ( 'No browser runtime errors: ' . format_value($errors) ) );
$report = {
    'version'    => '3.1.0',
    'assertions' => scalar( @{$checks} ),
    'checks'     => $checks,
    'errors'     => $errors,
    'limits'     =>
'Chromium exact shipped assets; synthetic Location/History/storage; real local Go WebSockets, no physical devices/public WAN.'
};
$out->child('report.json')->spew_utf8( json_text( $report, 1 ) );
$browser->close();
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
