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
    $a,         $ap,     $args,     $assets, $b,    $before, $browser, $case,  $cdp,
    $checks,    $code,   $contexts, $errors, $fb,   $field,  $gen,     $got,   $host,
    $icon_test, $line,   $offline,  $out,    $p,    $pages,  $parity,  $phone, $points,
    $pw,        $report, $result,   $root,   $rows, $st,     $t,       $tiny,  $wide
);

# v2.8 shared icons / dodgeable ricochet missiles shipped-client checks. Run TestBrowserFixture, then this script.
# The restricted browser cannot navigate to local pages. Assets, storage, location
# and History are isolated test adapters; gameplay uses real Go WebSocket sockets.
# History calls and encoded invite contents are checked, not real browser navigation.
$ap   = {};
$args = do {
    my %args = (
        'url'     => 'http://127.0.0.1:8790',
        'browser' => '/usr/bin/chromium',
        'output'  => 'test-output/missiles-v28'
    );
    my $help;
    GetOptions(
        'browser=s' => \$args{'browser'},
        'output=s'  => \$args{'output'},
        'help|h'    => \$help
      )
      or die 'Usage: perl missile_icons_browser.pl url --browser --output
';
    if ($help) {
        print 'Usage: perl missile_icons_browser.pl url --browser --output
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
    my ( $code, $power, $player, $speed, $shield, $cover, $missile_scene ) = @_;
    my ( $req, $res );
    $power         //= '';
    $player        //= 0;
    $speed         //= JSON::PP::false;
    $shield        //= JSON::PP::false;
    $cover         //= JSON::PP::false;
    $missile_scene //= '';
    $req = HTTP::Request->new(
        'POST',
        ( $args->{'url'} . '/_fixture/powerups' ),
        [ %{ { 'Content-Type' => 'application/json' } } ],
        Encode::encode_utf8(
            json_text(
                {
                    'code'         => $code,
                    'power'        => $power,
                    'player'       => $player,
                    'speed'        => $speed,
                    'shield'       => $shield,
                    'cover'        => $cover,
                    'missileScene' => $missile_scene
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
$offline   = main::load('OFFLINE');
$icon_test = '()=>{
 const result=[];const signatures=[];
 for(const icon of document.querySelectorAll(\'canvas[data-power-icon]\')){
  const copy=document.createElement(\'canvas\');copy.width=copy.height=icon.width;
  const c=copy.getContext(\'2d\');c.setTransform(copy.width/26,0,0,copy.width/26,copy.width/2,copy.height/2);
  __test.powerIcon(icon.dataset.powerIcon,c);
  const expected=c.getImageData(0,0,copy.width,copy.height).data,actual=icon.getContext(\'2d\').getImageData(0,0,copy.width,copy.height).data;
  if(!actual.some(v=>v>0)||!actual.every((v,i)=>v===expected[i]))throw Error(\'Legend differs from maze: \'+icon.dataset.powerIcon);
  if(icon.parentElement.textContent.trim())throw Error(\'Font substitute remains\');
  signatures.push(copy.toDataURL());result.push(\'Matching maze/legend pixels: \'+icon.dataset.powerIcon+\' at DPR \'+devicePixelRatio);
 }
 if(signatures.length!==7||new Set(signatures).size!==7)throw Error(\'Need seven distinct shared icons\');
 return result;
 }';
for $line ( @{ evaluate_js( $offline, $icon_test ) } ) {
    main::check( JSON::PP::true, $line );
}
$parity = decode_json( $root->parent->child('tests/missile-fixtures.json')->slurp_utf8 );
for $case ( @{$parity} ) {
    $got = evaluate_js(
        $offline, 'c=>{
   const T=__test;T.setMode(\'duel\');T.resetPreview();T.setPhase(\'playing\');T.clearBullets();
   T.walls.splice(0,T.walls.length,...c.world.walls);T.tanks.forEach((t,i)=>Object.assign(t,c.tanks[i]));
   const b={...c.bullet,dead:false,trail:[]};T.addBullet(b);
   for(let i=0;i<c.steps;i++){if(c.moveY)T.moveTank(T.tanks[1],0,c.moveY/60);T.updateBullets(1/60);}
   return {bullet:b,alive:T.tanks[1].alive};
  }', $case
    );
    for $field ( @{ [ 'x', 'y', 'vx', 'vy', 'life', 'age', 'rangeLeft', 'seekDelay', 'bounces', 'target' ] } )
    {
        assert_ok(
            (
                (
                    abs( ( ( $got->{'bullet'}->{$field} // 0 ) - ( $case->{'expected'}->{$field} // 0 ) ) ) <
                      1e-06
                )
            ),
            [ $case->{'name'}, $field, $got->{'bullet'}, $case->{'expected'} ]
        );
    }
    main::check(
        ( value_eq( $got->{'alive'}, $case->{'alive'} ) ),
        ( 'Go / JavaScript flight parity: ' . $case->{'name'} )
    );
}
$result = evaluate_js(
    $offline, '()=>{
 const T=__test,passed=[],ok=(v,s)=>{if(!v)throw Error(s);passed.push(s)};
 const setup=()=>{T.setMode(\'solo\');T.resetPreview();T.setPhase(\'playing\');T.clearBullets();const w=leqra.getState().world;
 T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});
 T.tanks.forEach((t,i)=>Object.assign(t,{x:100+i*150,y:210,angle:0,alive:false,invulnerable:0,shield:0,cooldown:0,power:null,speedTime:0}));return w;};
 const missile=(w,x,y)=>({id:10,owner:0,kind:\'homing\',target:-1,x,y,vx:235,vy:0,r:5,age:.2,life:(w.width+w.height)/235+.5,rangeLeft:w.width+w.height,seekDelay:0,dead:false,trail:[],bounces:0,color:\'#d2f65a\'});
 let w=setup(),p=T.tanks[0];p.alive=true;T.grantPower(p,\'homing\');T.fire(p);let b=T.bullets[0];ok(b.rangeLeft===w.width+w.height-28,\'Offline missile budget is half perimeter including muzzle\');
 w=setup();p=T.tanks[0];p.alive=true;p.x=w.width-24;T.grantPower(p,\'homing\');T.fire(p);b=T.bullets[0];ok(!b.dead&&b.vx<0&&b.bounces===1&&b.x<w.width-9,\'Muzzle-wall contact reflects, without crossing wall\');
 w=setup();b=missile(w,w.width-14,210);T.addBullet(b);T.updateBullets(1/30);ok(T.bullets.length===1&&b.vx<0&&b.bounces===1&&b.seekDelay>0,\'Offline wall contact survives, reflects, and clears steering\');
 w=setup();b=missile(w,100,210);b.rangeLeft=1.25;T.addBullet(b);T.updateBullets(1/60);ok(b.dead&&b.rangeLeft===0&&Math.abs(b.x-101.25)<1e-7,\'Offline range exhaustion cannot overshoot mid-tick\');
 w=setup();b=missile(w,w.width-14,210);T.addBullet(b);T.tanks[1].alive=true;T.tanks[1].x=w.width-120;
 const before=JSON.stringify(b),segments=T.forecastThreats(T.tanks[1],.65);ok(segments.some(s=>s.vx<0)&&segments.some(s=>s.vx>0),\'Bot dodge forecast includes both incoming and reflected missile\');ok(JSON.stringify(b)===before,\'Bot forecast does not mutate live projectile\');
 const projected=T.projectOnlineBullet(b,.1);ok(projected.bounces===1&&projected.vx<0&&projected.x<b.x&&projected.rangeLeft<b.rangeLeft,\'Online projectile smoothing continues along reflected wall path\');ok(JSON.stringify(b)===before,\'Visual extrapolation does not mutate authoritative snapshot\');
 b=missile(w,100,210);b.rangeLeft=1.25;const short=T.projectOnlineBullet(b,.1);ok(Math.abs(short.x-101.25)<1e-7&&short.rangeLeft===0,\'Online visual extrapolation respects half-perimeter budget\');
 w=setup();T.tanks[0].alive=true;T.tanks[0].x=400;T.tanks[0].y=260;T.tanks[1].alive=true;T.tanks[1].x=100;T.tanks[2].alive=true;T.tanks[2].x=180;
 b=missile(w,135,210);b.owner=1;T.steerMissile(b,1/60);ok(b.target===0&&b.vy>0,\'Bot missile ignores closer allied bot\');
 T.tanks[0].alive=false;T.tanks[2].x=220;T.tanks[2].shield=10;b.target=-1;b.seekDelay=0;b.vx=235;b.vy=0;T.addBullet(b);for(let i=0;i<45;i++)T.updateBullets(1/60);ok(T.tanks[2].alive&&T.tanks[2].shield===10,\'Bot missile collision still cannot harm allied shield or tank\');
 T.setPhase(\'menu\');T.resetPreview();return passed;
 }'
);
for $line ( @{$result} ) {
    main::check( JSON::PP::true, $line );
}
$offline->close();
$host = main::load('HOST');
$host->locator('[data-mode=online]')->click();
$host->locator('#createRoomBtn')->click();
main::connected($host);
$code  = main::state($host)->{'online'}->{'code'};
$phone = main::load( 'PHONE',  $code, [ 390, 844 ] );
$tiny  = main::load( 'POCKET', $code, [ 320, 568 ] );
$wide  = main::load( 'WIDE',   $code, [ 844, 390 ] );
$pages = [ $host, $phone, $tiny, $wide ];

for $p ( @{$pages} ) {
    wait_js( $p, 'leqra.getState().online?.players.length===4' );
    $p->locator('#readyBtn')->click();
}
$host->locator('#startRoomBtn')->click();
for $p ( @{$pages} ) {
    wait_js( $p, 'leqra.getState().phase==="playing"' );
}
for $line ( @{ evaluate_js( $phone, $icon_test ) } ) {
    main::check( JSON::PP::true, $line );
}

sub scenario {
    my ($kwargs) = @_;
    my ( $data, $p );
    $kwargs //= {};
    $data = main::fixture($code);
    for $p ( @{$pages} ) {
        wait_js( $p, 'g=>__messages.some(m=>m.type==="state"&&m.generation===g)', $data->{'generation'}, {} );
    }
    return $data->{'generation'};
}
$gen = main::scenario( { 'power' => 'homing', 'cover' => JSON::PP::true } );
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(70) );
$host->keyboard()->up('Space');
for $p ( @{$pages} ) {
    wait_js(
        $p,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.bounces>0&&b.vx<0&&b.rangeLeft>0))',
        $gen,
        {}
    );
}
main::check( JSON::PP::true, 'All four clients receive a live reflected homing missile' );
main::check(
    evaluate_js(
        $host,
'g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.bullets).filter(b=>b.kind==="homing").every(b=>b.x<=325.001)',
        $gen
    ),
    'Server missile stays on near side of intervening wall'
);
main::check(
    (
        [
            map {
                my $t = $_;
                truth_value( ( value_eq( $t->{'id'}, 1 ) ) ) ? ($t) : ()
            } @{ main::state($host)->{'tanks'} }
        ]->[0] // undef
    )->{'alive'},
    'Cover still protects opponent while missile ricochets'
);
evaluate_js( $host, 'document.querySelector(".sidebar").scrollTop=10000' );
$host->screenshot( { path => format_value( $out->child('shared-icons-and-wall-bounce.png') ) } );
$tiny->screenshot( { path => format_value( $out->child('missile-320x568.png') ) } );
$gen = main::scenario( { 'power' => 'homing', 'missile_scene' => 'dodge' } );
$phone->keyboard()->down('KeyW');
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(70) );
$host->keyboard()->up('Space');
$Leqra::Browser::HANDLE->await( $phone->waitForTimeout(920) );
$phone->keyboard()->up('KeyW');
main::check(
    (
        [
            map {
                my $t = $_;
                truth_value( ( value_eq( $t->{'id'}, 1 ) ) ) ? ($t) : ()
            } @{ main::state($phone)->{'tanks'} }
        ]->[0] // undef
    )->{'alive'},
    'Normal-speed online tank survives a sideways dodge'
);
main::check(
    evaluate_js(
        $host,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"&&b.age>.5&&b.target===-1))',
        $gen
    ),
    'Dodge breaks server missile lock'
);
$gen = main::scenario( { 'power' => 'homing', 'missile_scene' => 'range' } );
$host->keyboard()->down('Space');
$Leqra::Browser::HANDLE->await( $host->waitForTimeout(70) );
$host->keyboard()->up('Space');
wait_js( $host,
    'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.bullets.some(b=>b.kind==="homing"))',
    $gen, {} );
wait_js(
    $host,
'g=>__messages.some(m=>m.type==="state"&&m.generation===g&&m.events.some(e=>e.type==="impact"&&e.radius===20))',
    $gen,
    { timeout => 12000 }
);
$rows = evaluate_js(
    $host,
'g=>__messages.filter(m=>m.type==="state"&&m.generation===g).flatMap(m=>m.bullets.filter(b=>b.kind==="homing"))',
    $gen
);
main::check(
    (
        do {
            my $boolean_value = !scalar(
                grep {
                    my $b = $_;
                    !( ( ( 0 < $b->{'rangeLeft'} ) && ( $b->{'rangeLeft'} <= 1680 ) ) )
                } @{$rows}
            );
            truth_value($boolean_value)
              ? !scalar(
                grep {
                    my ( $a, $b ) = @{$_};
                    !( ( ( $b->{'rangeLeft'} <= $a->{'rangeLeft'} ) ) )
                  } @{
                    [
                        map {
                            my $i = $_;
                            [ $rows->[$i], array_slice( $rows, 1, undef )->[$i] ]
                        } 0 .. min( $#{$rows}, $#{ array_slice( $rows, 1, undef ) } )
                    ]
                  }
              )
              : $boolean_value;
        }
    ),
    'Live missile has one monotonically decreasing half-perimeter budget'
);
main::check(
    (
        do {
            my $boolean_value = scalar( grep { my $b = $_; ( ( $b->{'bounces'} >= 1 ) ) } @{$rows} );
            truth_value($boolean_value)
              ? ( ( $rows->[ (-1) ]->{'rangeLeft'} < 12 ) )
              : $boolean_value;
        }
    ),
    'Live missile spends its remaining range after multiple wall contacts'
);
for $p ( @{$pages} ) {
    wait_js( $p, 'leqra.getState().bulletCount===0' );
}
main::check( JSON::PP::true, 'Range-exhausted missile disappears for all clients' );
$gen = main::scenario(
    {
        'power'  => 'homing',
        'player' => 1,
        'speed'  => JSON::PP::true,
        'shield' => JSON::PP::true
    }
);
wait_js( $phone, 'leqra.getState().tanks.find(t=>t.id===1)?.power==="homing"' );
$cdp    = $phone->context()->newCDPSession($phone);
$st     = $phone->locator('#stickBase')->boundingBox();
$fb     = $phone->locator('#fireBtn')->boundingBox();
$before = (
    [
        map {
            my $t = $_;
            truth_value( ( value_eq( $t->{'id'}, 1 ) ) ) ? ($t) : ()
        } @{ main::state($phone)->{'tanks'} }
    ]->[0] // undef
);
$points = [
    {
        'x'  => ( ( $st->{'x'} + ( $st->{'width'} / 2 ) ) + 35 ),
        'y'  => ( $st->{'y'} + ( $st->{'height'} / 2 ) ),
        'id' => 11
    },
    {
        'x'  => ( $fb->{'x'} + ( $fb->{'width'} / 2 ) ),
        'y'  => ( $fb->{'y'} + ( $fb->{'height'} / 2 ) ),
        'id' => 12
    }
];
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchStart', 'touchPoints' => $points } );
$Leqra::Browser::HANDLE->await( $phone->waitForTimeout(330) );
main::check(
    (
        do {
            my $boolean_value = (
                (
                    (
                        [
                            map {
                                my $t = $_;
                                truth_value( ( value_eq( $t->{'id'}, 1 ) ) )
                                  ? ($t)
                                  : ()
                            } @{ main::state($phone)->{'tanks'} }
                        ]->[0] // undef
                    )->{'x'} > ( $before->{'x'} + 30 )
                )
            );
            truth_value($boolean_value)
              ? evaluate_js( $phone->locator('#fireBtn'), 'e=>e.classList.contains("held")' )
              : $boolean_value;
        }
    ),
    'Simultaneous mobile steering and missile firing still work'
);
$cdp->send( 'Input.dispatchTouchEvent', { 'type' => 'touchEnd', 'touchPoints' => [] } );
for $p ( @{ [ $tiny, $phone, $wide ] } ) {
    main::check(
        evaluate_js( $p, 'document.documentElement.scrollWidth<=innerWidth' ),
        ( 'No horizontal overflow at ' . format_value( $p->viewportSize() ) )
    );
}
main::check( ( !truth_value($errors) ), 'No JavaScript exceptions in icon/missile checks' );
$report = {
    'checks_passed'          => scalar( @{$checks} ),
    'checks'                 => $checks,
    'javascript_errors'      => $errors,
    'browser_version'        => $browser->version(),
    'isolated_assets'        => JSON::PP::true,
    'server'                 => 'local Go WebSocket fixture',
    'go_client_parity_cases' => scalar( @{$parity} ),
    'layouts'                => [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ]
};
$out->child('missile-icons-results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", json_text( $report, 1 ) ), "\n" );
$browser->close();
