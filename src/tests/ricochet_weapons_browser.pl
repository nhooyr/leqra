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
    $a,      $ap,       $args, $assets, $b,     $beams, $browser, $cdp,   $checks,
    $code,   $contexts, $e,    $errors, $fire,  $gen,   $host,    $label, $latest,
    $length, $offline,  $out,  $p,      $pages, $phone, $pts,     $pw,    $rect,
    $result, $root,     $size, $st,     $steer, $tiny,  $wide
);

# v2.7 ricochet / remote grenade shipped-client checks. Run TestBrowserFixture, then this script.
# The restricted browser cannot navigate to local pages. Assets, storage, location
# and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
# History calls and encoded invite contents are checked, not real browser navigation.
$ap   = {};
$args = do {
    my %args = (
        'url'     => 'http://127.0.0.1:8790',
        'browser' => '/usr/bin/chromium',
        'output'  => 'test-output/weapons-v27'
    );
    my $help;
    GetOptions(
        'browser=s' => \$args{'browser'},
        'output=s'  => \$args{'output'},
        'help|h'    => \$help
      )
      or die 'Usage: perl ricochet_weapons_browser.pl url --browser --output
';
    if ($help) {
        print 'Usage: perl ricochet_weapons_browser.pl url --browser --output
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
$checks = [];
$errors = [];

sub check {
    my ( $v, $label ) = @_;
    assert_ok( $v, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub state {
    my ($p) = @_;
    return evaluate_js( $p, 'leqra.getState()' );
}

sub fixture {
    my ( $code, $power, $player, $speed, $shield, $cover ) = @_;
    my ( $req, $res );
    $power  //= '';
    $player //= 0;
    $speed  //= JSON::PP::false;
    $shield //= JSON::PP::false;
    $cover  //= JSON::PP::false;
    $req = HTTP::Request->new(
        'POST',
        ( $args->{'url'} . '/_fixture/powerups' ),
        [ %{ { 'Content-Type' => 'application/json' } } ],
        Encode::encode_utf8(
            json_text(
                {
                    'code'   => $code,
                    'power'  => $power,
                    'player' => $player,
                    'speed'  => $speed,
                    'shield' => $shield,
                    'cover'  => $cover
                }
            )
        )
    );
    $res = request_ok($req);
    return decode_json( $res->content );
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
    my ( $name, $code, $size, $session, $history_throws ) = @_;
    my ( $context, $html, $js, $mobile, $p, $pos, $url, $ws );
    $name           //= 'PILOT';
    $code           //= undef;
    $size           //= [ 1365, 950 ];
    $session        //= undef;
    $history_throws //= JSON::PP::false;
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
    $url = (
        'http://game.test/tanks/?test=1'
          . (
            truth_value( ( defined($code) ) )
            ? ( '&' . query_string( { 'room' => $code } ) )
            : ''
          )
    );
    $ws   = ( replace_text( replace_text( $args->{'url'}, 'http:', 'ws:' ), 'https:', 'wss:' ) . '/ws' );
    $html = replace_text(
        replace_text(
            replace_text(
                replace_re( '<link[^>]*>', '', $root->child('index.html')->slurp_utf8 ),
                '<script src="game.js" defer></script>', ''
            ),
            '<script src="netcode.js" defer></script>',
            ''
        ),
        '</head>',
        ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' )
    );
    $p->setContent($html);
    evaluate_js(
        $p, '([url,ws,name,session,historyThrows])=>{
   window.__location=new URL(url);window.__historyCalls=[];window.__copied=\'\';window.__sockets=[];window.__messages=[];window.__sent=[];
   const RealSocket=WebSocket;window.WebSocket=class extends RealSocket{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};
   const store=initial=>{const data={...initial};return{getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]}};
   Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':name,\'leqra.muted\':\'1\'})});
   Object.defineProperty(window,\'sessionStorage\',{value:store(session?{\'leqra.session\':JSON.stringify(session)}:{})});
   history.replaceState=(s,t,u)=>{if(historyThrows)throw Error(\'Restricted History\');__historyCalls.push(String(u));__location.href=String(u)};
   Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{__copied=v}}});
  }', [ $url, $ws, $name, $session, $history_throws ]
    );
    $js  = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
    $pos = rindex( $js, '})()' );
    $js  = ( ( substr( $js, 0, $pos - 0 ) . '})(window.__location);' ) . substr( $js, ( $pos + 4 ) ) );
    $p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.leqra' );
    return $p;
}

sub connected {
    my ($p) = @_;
    wait_js( $p, 'leqra.getState().online?.connected', undef, { timeout => 10000 } );
}
$offline = main::load('OFFLINE');
$result  = evaluate_js(
    $offline, '()=>{
  const T=__test,passed=[];const ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
  const setup=(mode=\'solo\')=>{
   T.setMode(mode);T.resetPreview();T.clearBullets();T.setPhase(\'playing\');
   const w=leqra.getState().world;
   T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
   T.tanks.forEach((t,i)=>Object.assign(t,{x:i?600+i*100:120,y:i?550:100,angle:0,alive:true,invulnerable:0,shield:0,speedTime:0,power:null,powerTime:0,charges:0,cooldown:0,vx:0,vy:0,fireHeld:false,fireBlocked:false}));
   return T.tanks;
  };
  const tap=code=>{window.dispatchEvent(new KeyboardEvent(\'keydown\',{code}));window.dispatchEvent(new KeyboardEvent(\'keyup\',{code}));};
  const length=ps=>ps.reduce((v,p,i)=>v+(i?Math.hypot(p.x-ps[i-1].x,p.y-ps[i-1].y):0),0);
  let ts=setup(),w=leqra.getState().world;ts[1].x=220;ts[1].y=300;ts[0].angle=Math.atan2(200,2*(w.width-7)-220-120);
  T.grantPower(ts[0],\'laser\');let beam=T.laserTrace(ts[0]);
  ok(beam.points.length>=3&&beam.targets.includes(ts[1])&&beam.bounces>=1,\'Offline laser acquires tank after reflection\');
  T.fire(ts[0]);ok(!ts[1].alive&&ts[0].alive,\'Banked laser kills opponent and retains shooter immunity\');
  ok(T.traces.at(-1).points.length===3,\'Offline rendered beam preserves complete ricochet polyline\');
  ts=setup();for(const t of ts.slice(1))t.alive=false;
  for(const angle of [0,.17,Math.PI/4,Math.PI/2,2.9]){ts[0].angle=angle;beam=T.laserTrace(ts[0]);ok(Math.abs(length(beam.points)-(4*(w.width+w.height)-28))<.00001,\'Whole laser path uses one perimeter budget: \'+angle);}
  ts=setup();ts[0].x=129;T.walls.push({x:150,y:0,w:8,h:w.height});beam=T.laserTrace(ts[0]);
  ok(beam.points[1].x===147&&beam.points.slice(1).every(p=>p.x<=147.00001),\'Barrel against wall reflects without clipping through it\');
  ts=setup();ts[0].x=220;ts[0].y=300;ts[1].x=120;ts[1].y=100;ts[1].angle=Math.atan2(200,2*(w.width-7)-220-120);
  ts[2].x=ts[1].x+100;ts[2].y=ts[1].y+100*Math.tan(ts[1].angle);ts[2].shield=10;T.grantPower(ts[1],\'laser\');T.fire(ts[1]);
  ok(!ts[0].alive&&ts[1].alive&&ts[2].alive&&ts[2].shield===10,\'Reflected bot laser passes through allies and their shields\');

  ts=setup();T.grantPower(ts[0],\'grenade\');T.weaponControl(ts[0],true,true);let b=T.ownedGrenades(ts[0])[0];
  ok(b&&b.life===5&&ts[0].charges===2,\'Offline grenade launches with exactly five-second fuse\');
  b.x=400;b.y=100;b.vx=b.vy=0;
  for(let i=0;i<120;i++){ts[0].cooldown=0;T.weaponControl(ts[0],true,false)}
  ok(!b.dead&&T.ownedGrenades(ts[0]).length===1&&ts[0].charges===2,\'Holding Fire neither detonates nor repeats a grenade\');
  T.updateHUD(true);ok(document.getElementById(\'fireLabel\').textContent===\'BOOM\'&&document.getElementById(\'weaponLabel\').textContent.startsWith(\'DETONATE\'),\'Armed grenade switches Fire and HUD to detonation\');
  T.weaponControl(ts[0],false,false);T.weaponControl(ts[0],true,true);
  ok(b.dead&&ts[0].charges===2,\'Second press detonates without consuming a charge\');
  for(let i=0;i<120;i++){ts[0].cooldown=0;T.weaponControl(ts[0],true,false)}
  ok(T.bullets.length===1,\'Holding detonation does not also throw/shoot\');
  T.weaponControl(ts[0],false,false);T.weaponControl(ts[0],true,true);
  ok(T.ownedGrenades(ts[0]).length===1&&ts[0].charges===1,\'Release and press permits the next grenade\');

  ts=setup();T.grantPower(ts[0],\'grenade\');ts[0].charges=1;tap(\'Space\');T.humanControl(ts[0],1/120);b=T.ownedGrenades(ts[0])[0];
  ok(b&&!ts[0].power,\'Sub-tick keyboard tap launches the final grenade\');
  b.x=400;b.y=100;b.vx=b.vy=0;T.updateHUD(true);ok(document.getElementById(\'fireLabel\').textContent===\'BOOM\',\'Final grenade retains detonation UI after weapon expiry\');
  tap(\'Space\');T.humanControl(ts[0],1/120);ok(b.dead&&T.bullets.length===1,\'Sub-tick second tap detonates final grenade, not standard shot\');

  ts=setup();T.grantPower(ts[0],\'grenade\');T.weaponControl(ts[0],true,true);b=T.ownedGrenades(ts[0])[0];b.x=400;b.y=100;b.vx=b.vy=0;T.clearInput();
  window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:\'Space\',repeat:true}));T.humanControl(ts[0],1/120);
  ok(!b.dead,\'OS key repeat after focus/input reset cannot synthesize a fresh detonation\');

  ts=setup(\'duel\');T.grantPower(ts[1],\'grenade\');tap(\'Enter\');T.humanControl(ts[1],1/120);b=T.ownedGrenades(ts[1])[0];
  ok(!!b,\'Local second player uses Enter to throw\');b.x=400;b.y=100;b.vx=b.vy=0;
  tap(\'Space\');T.humanControl(ts[0],1/120);ok(!b.dead,\'Player one cannot trigger player two grenade\');
  tap(\'Enter\');T.humanControl(ts[1],1/120);ok(b.dead,\'Local second player uses Enter again to detonate\');

  ts=setup();T.grantPower(ts[0],\'grenade\');T.fire(ts[0]);b=T.bullets[0];b.x=400;b.y=100;b.vx=b.vy=0;
  for(let i=0;i<599;i++)T.updateBullets(1/120);ok(!b.dead,\'Grenade stays live until immediately before five seconds\');
  T.updateBullets(1/120);ok(b.dead&&T.bullets.length===0,\'Grenade automatically explodes at five seconds\');

  ts=setup();T.grantPower(ts[1],\'grenade\');T.fire(ts[1]);b=T.ownedGrenades(ts[1])[0];b.x=ts[0].x+30;b.y=ts[0].y;b.vx=b.vy=0;ts[1].ai.think=0;
  T.botControl(ts[1],1/120);ok(b.dead&&!ts[0].alive&&ts[1].alive&&ts[2].alive,\'Bots use early detonation only against the player\');
  T.setPhase(\'menu\');T.resetPreview();return passed;
 }'
);
for $label ( @{$result} ) {
    main::check( JSON::PP::true, $label );
}
$offline->close();
$host = main::load('HOST');
$host->locator('[data-mode=online]')->click();
main::check(
    (
        do {
            my $boolean_value =
              ( !( contains_value( $host->locator('#netStatus')->innerText(), 'Leave blank' ) ) );
            truth_value($boolean_value)
              ? ( !( contains_value( $host->locator('#netStatus')->innerText(), 'random room' ) ) )
              : $boolean_value;
        }
    ),
    'Random-room hint is removed from online screen'
);
$code = ( 'leqra + boom 💥 ' . unpack( "H*", random_bytes(3) ) );
$host->locator('#joinCode')->fill($code);
$host->locator('#createRoomBtn')->click();
main::connected($host);
main::check( ( value_eq( evaluate_js( $host, 'new URL(__location.href).searchParams.get("room")' ), $code ) ),
    'Creating custom room still updates invite URL' );
$phone = main::load( 'PHONE', $code, [ 390, 844 ] );
$tiny  = main::load( 'TINY',  $code, [ 320, 568 ] );
$wide  = main::load( 'WIDE',  $code, [ 844, 390 ] );
$pages = [ $host, $phone, $tiny, $wide ];

for $p ( @{$pages} ) {
    main::connected($p);
    wait_js( $p, 'leqra.getState().online.players.length===4' );
    $p->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $p ( @{$pages} ) {
    wait_js( $p, 'leqra.getState().phase==="playing"' );
}

sub scenario {
    my ( $power, $player, $cover, $speed, $shield, $charges ) = @_;
    my ( $body, $data, $p, $res );
    $player  //= 0;
    $cover   //= JSON::PP::false;
    $speed   //= JSON::PP::false;
    $shield  //= JSON::PP::false;
    $charges //= undef;
    $body = {
        'code'   => $code,
        'power'  => $power,
        'player' => $player,
        'cover'  => $cover,
        'speed'  => $speed,
        'shield' => $shield
    };

    if ( truth_value( ( defined($charges) ) ) ) {
        $body->{'charges'} = $charges;
    }
    $res = request_ok(
        HTTP::Request->new(
            'POST',
            ( $args->{'url'} . '/_fixture/powerups' ),
            [ %{ { 'Content-Type' => 'application/json' } } ],
            Encode::encode_utf8( json_text($body) )
        )
    );
    $data = decode_json( $res->content );
    for $p ( @{$pages} ) {
        wait_js( $p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g)', $data->{'generation'}, {} );
        $Leqra::Browser::HANDLE->await( $p->waitForTimeout(50) );
    }
    return $data->{'generation'};
}

sub events {
    my ( $p, $gen, $kind ) = @_;
    return evaluate_js(
        $p,
'([g,k])=>{const all=__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.events||[]).filter(e=>e.type===k&&e.generation===g);return [...new Map(all.map(e=>[e.id,e])).values()]}',
        [ $gen, $kind ]
    );
}

sub tank {
    my ( $p, $id ) = @_;
    my ($t);
    return (
        [
            map {
                my $t = $_;
                truth_value( ( value_eq( $t->{'id'}, $id ) ) ) ? ($t) : ()
            } @{ main::state($p)->{'tanks'} }
        ]->[0] // undef
    );
}

sub press {
    my ( $p, $ms ) = @_;
    $ms //= 70;
    $p->keyboard()->down('Space');
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout($ms) );
    $p->keyboard()->up('Space');
}
$gen = main::scenario( 'laser', 2, undef, undef, undef, undef );
$tiny->keyboard()->down('Space');
wait_js(
    $tiny,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',
    $gen,
    {}
);
$tiny->keyboard()->up('Space');
$tiny->screenshot( { path => format_value( $out->child('ricochet-laser-320x568.png') ) } );
for $p ( @{$pages} ) {
    wait_js(
        $p,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',
        $gen,
        {}
    );
}
$beams =
  [ map { my $p = $_; main::events( $p, $gen, 'laser' )->[0] } @{$pages} ];
main::check(
    !scalar(
        grep {
            my $e = $_;
            !( ( value_eq( $e->{'points'}, $beams->[0]->{'points'} ) ) )
        } @{$beams}
    ),
    'Four online clients receive identical full ricochet path'
);
main::check(
    ( ( scalar( @{ $beams->[0]->{'points'} } ) >= 3 ) ),
    'Server online laser has at least one reflected segment'
);
wait_js( $tiny, '!leqra.getState().tanks.find(t=>t.id===1).alive' );
main::check(
    (
        do {
            my $boolean_value = main::tank( $tiny, 2 )->{'alive'};
            truth_value($boolean_value)
              ? ( value_eq( main::tank( $tiny, 2 )->{'charges'}, 2 ) )
              : $boolean_value;
        }
    ),
    'Online reflected hit consumes one charge without self-damage'
);
$gen = main::scenario( 'laser', undef, JSON::PP::true, undef, undef, undef );
main::press($host);
wait_js(
    $host,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="laser"&&e.generation===g))',
    $gen,
    {}
);
$e      = main::events( $host, $gen, 'laser' )->[0];
$pts    = $e->{'points'};
$length = sum(
    @{
        [
            map {
                my ( $a, $b ) = @{$_};
                ( ( ( ( $b->{'x'} - $a->{'x'} )**2 ) + ( ( $b->{'y'} - $a->{'y'} )**2 ) )**0.5 )
              } @{
                [
                    map {
                        my $i = $_;
                        [ $pts->[$i], array_slice( $pts, 1, undef )->[$i] ]
                    } 0 .. min( $#{$pts}, $#{ array_slice( $pts, 1, undef ) } )
                ]
              }
        ]
    }
);
main::check(
    (
        do {
            my $boolean_value = ( ( scalar( @{$pts} ) > 4 ) );
            truth_value($boolean_value)
              ? ( ( abs( ( $length - ( ( 2 * ( 1008 + 672 ) ) - 28 ) ) ) < 1e-05 ) )
              : $boolean_value;
        }
    ),
    'Online many-bounce miss is capped by total maze perimeter'
);
main::check(
    (
        do {
            my $boolean_value = main::tank( $host, 1 )->{'alive'};
            truth_value($boolean_value)
              ? ( ( max( @{ [ map { my $p = $_; $p->{'x'} } @{$pts} ] } ) <= 327.00001 ) )
              : $boolean_value;
        }
    ),
    'Online laser reflects at cover rather than tunneling'
);
$host->screenshot( { path => format_value( $out->child('laser-path-desktop.png') ) } );
$gen = main::scenario('grenade');
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(1200) );
$latest = evaluate_js( $host, 'g=>__messages.filter(m=>m.type==="state"&&m.generation===g).at(-1)', $gen );
main::check(
    (
        do {
            my $boolean_value = (
                value_eq(
                    scalar(
                        @{
                            [
                                map {
                                    my $b = $_;
                                    truth_value( ( value_eq( ( $b->{'kind'} // undef ), 'grenade' ) ) )
                                      ? ($b)
                                      : ()
                                } @{ $latest->{'bullets'} }
                            ]
                        }
                    ),
                    1
                )
            );
            truth_value($boolean_value)
              ? do {
                my $boolean_value =
                  ( value_eq( main::tank( $host, 0 )->{'charges'}, 2 ) );
                truth_value($boolean_value)
                  ? ( !truth_value( main::events( $host, $gen, 'blast' ) ) )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'Online held Fire launches exactly one grenade, without detonation'
);
main::check( ( contains_value( $host->locator('#weaponLabel')->innerText(), 'DETONATE' ) ),
    'Online HUD advertises early detonation and countdown' );
$host->keyboard()->up('Space');
main::press( $host, 1000 );
for $p ( @{$pages} ) {
    wait_js(
        $p,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',
        $gen,
        {}
    );
}
main::check(
    (
        do {
            my $boolean_value = ( value_eq( scalar( @{ main::events( $host, $gen, 'blast' ) } ), 1 ) );
            truth_value($boolean_value)
              ? ( value_eq( main::tank( $host, 0 )->{'charges'}, 2 ) )
              : $boolean_value;
        }
    ),
    'Fresh online press detonates once; holding does not throw another'
);
wait_js( $host, '!leqra.getState().tanks.find(t=>t.id===1).alive' );
main::check( main::tank( $host, 0 )->{'alive'},
    'Early grenade blast kills nearby enemy while distant owner survives' );
$gen = main::scenario( 'grenade', undef, undef, undef, undef, 1 );
main::press($host);
wait_js( $host,
'!leqra.getState().tanks.find(t=>t.id===0).power&&document.getElementById("fireLabel").textContent==="BOOM"'
);
main::check( JSON::PP::true, 'Online final-charge grenade stays remotely detonatable' );
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(1000) );
main::press( $host, 400 );
wait_js(
    $host,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',
    $gen,
    {}
);
main::check(
    ( value_eq( main::state($host)->{'bulletCount'}, 0 ) ),
    'Detonating the final grenade does not also fire a standard shell'
);
$gen = main::scenario('grenade');
main::press($host);
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(2700) );
main::check(
    ( !truth_value( main::events( $host, $gen, 'blast' ) ) ),
    'Untriggered online grenade remains live beyond old 1.6-second fuse'
);

for $p ( @{$pages} ) {
    wait_js(
        $p,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.generation===g))',
        $gen,
        { timeout => 6000 }
    );
}
main::check(
    ( value_eq( scalar( @{ main::events( $host, $gen, 'blast' ) } ), 1 ) ),
    'Five-second automatic fallback explodes exactly once on all clients'
);
$gen  = main::scenario( 'grenade', 2, undef, JSON::PP::true, JSON::PP::true, undef );
$cdp  = $tiny->context()->newCDPSession($tiny);
$rect = $tiny->locator('#fireBtn')->boundingBox();
$st   = $tiny->locator('#stickBase')->boundingBox();
$fire = {
    'x'  => ( $rect->{'x'} + ( $rect->{'width'} / 2 ) ),
    'y'  => ( $rect->{'y'} + ( $rect->{'height'} / 2 ) ),
    'id' => 12
};
$steer = {
    'x'  => ( ( $st->{'x'} + ( $st->{'width'} / 2 ) ) - 20 ),
    'y'  => ( $st->{'y'} + ( $st->{'height'} / 2 ) ),
    'id' => 11
};
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => [ $steer, $fire ] } );
$Leqra::Browser::HANDLE->await( $tiny->waitForTimeout(400) );
wait_js( $tiny, 'document.getElementById("fireLabel").textContent==="BOOM"' );
main::check(
    ( value_eq( $tiny->locator('#fireBtn')->getAttribute('aria-label'), 'Press to detonate your grenade' ) ),
    'Mobile Fire button shows accessible detonation action'
);
main::check(
    evaluate_js( $tiny, 'document.documentElement.scrollWidth<=innerWidth' ),
    'Armed grenade controls fit compact phone without horizontal overflow'
);
$tiny->screenshot( { path => format_value( $out->child('grenade-armed-320x568.png') ) } );
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
$Leqra::Browser::HANDLE->await( $tiny->waitForTimeout(100) );
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => [$fire] } );
$Leqra::Browser::HANDLE->await( $tiny->waitForTimeout(70) );
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
wait_js(
    $tiny,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="blast"&&e.owner===2&&e.generation===g))',
    $gen,
    {}
);
main::check( JSON::PP::true,
    'Second mobile tap triggers server-authoritative detonation while steering remains supported' );

for my $item ( @{ [ [ $phone, [ 390, 844 ] ], [ $wide, [ 844, 390 ] ] ] } ) {
    my $tuple_185_5 = $item;
    my $p           = $tuple_185_5->[0];
    my $size        = $tuple_185_5->[1];
    my $gen =
      main::scenario( 'grenade', main::state($p)->{'online'}->{'id'}, undef, undef, JSON::PP::true, undef );
    main::press($p);
    $Leqra::Browser::HANDLE->await( $p->waitForTimeout(100) );
    main::check(
        evaluate_js( $p, 'document.documentElement.scrollWidth<=innerWidth' ),
        ( 'No overflow in armed grenade layout ' . format_value($size) )
    );
    $p->screenshot(
        {
            path => format_value( $out->child( ( 'grenade-' . $size->[0] . 'x' . $size->[1] . '.png' ) ) )
        }
    );
}
main::check( ( !truth_value($errors) ), 'No browser JavaScript errors' );
$browser->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'checks_passed' => scalar( @{$checks} ),
            'checks'        => $checks,
            'errors'        => $errors,
            'limitations'   =>
'Chromium emulation; synthetic location/History/storage, exact shipped assets and live Go fixture sockets. Not real navigation, physical phones or public hosting.'
        },
        1
    )
);
print( join( " ", 'PASSED', scalar( @{$checks} ) ), "\n" );
