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
    $a,     $ap,      $assets, $b,     $before,  $c,   $checks, $code,   $contexts,
    $count, $counts,  $data,   $equal, $errors,  $gen, $gid,    $guest,  $host,
    $html,  $i,       $js,     $kind,  $matched, $n,   $ok,     $out,    $p,
    $p2id,  $pellets, $pid,    $power, $preset,  $pw,  $r,      $radius, $raw,
    $size,  $skin,    $spec,   $speed, $state,   $tag, $token,  $viewer, $web
);

# v4.4 exact-asset Chromium checks. About:blank injection + loopback fixture.
# No production grant endpoint; screenshots and checks are from the shipped code.
$ap = {};
$a  = do {
    my %args = (
        'url'        => 'http://127.0.0.1:8445',
        'output'     => 'test-output/arsenal44',
        'local_only' => undef
    );
    my $help;
    GetOptions(
        'url=s'       => \$args{'url'},
        'output=s'    => \$args{'output'},
        'local-only!' => \$args{'local_only'},
        'help|h'      => \$help
      )
      or die 'Usage: perl arsenal44_browser.pl --url --output --local-only
';
    if ($help) {
        print 'Usage: perl arsenal44_browser.pl --url --output --local-only
';
        exit 0;
    }
    \%args;
};
$r      = path($0)->absolute->parent(2);
$web    = $r->child('web');
$assets = asset_directory($web);
$out    = path( $a->{'output'} );
$out->mkpath;
$html = replace_text(
    replace_re( '<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8 ),
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
$contexts = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub wait {
    my ( $p, $s, $kwargs ) = @_;
    $kwargs //= {};
    return wait_js( $p, $s, undef, { polling => 30 } );
}

sub load {
    my ( $b, $size, $scheme, $live, $code, $watch, $name ) = @_;
    my ( $c, $f, $h, $mobile, $p, $q, $w );
    $size   //= [ 1365, 950 ];
    $scheme //= 'dark';
    $live   //= JSON::PP::false;
    $code   //= undef;
    $watch  //= JSON::PP::false;
    $name   //= 'PILOT';
    my $tuple_20_1 = $size;
    $w      = $tuple_20_1->[0];
    $h      = $tuple_20_1->[1];
    $mobile = (
        do {
            my $boolean_value = ( ( $w < 760 ) );
            truth_value($boolean_value) ? $boolean_value : ( ( $h < 620 ) );
        }
    );
    $c = $b->newContext(
        {
            viewport          => { 'width' => $w, 'height' => $h },
            hasTouch          => $mobile,
            isMobile          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 ),
            colorScheme       => $scheme
        }
    );
    push( @{$contexts}, $c );
    $p = $c->newPage();
    $p->setDefaultTimeout(9000);
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->setContent($html);
    $q = { 'test' => '1' };

    if ( truth_value($code) ) {
        $q->{'room'} = $code;
    }
    if ( truth_value($watch) ) {
        $q->{'spectate'} = '1';
    }
    evaluate_js(
        $p,
'a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};
 for(const name of [\'localStorage\',\'sessionStorage\']){const d=name===\'localStorage\'?{\'leqra.name\':a.name,\'leqra.muted\':\'1\'}:{};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}
 if(!a.live)window.requestAnimationFrame=()=>0;
 const WS=WebSocket;window.WebSocket=class extends WS{constructor(...args){super(...args);this.addEventListener(\'message\',e=>{const s=JSON.parse(e.data);if(s.type===\'state\')window.__lastRaw=s;});}};
 }',
        {
            'url'  => ( ( $a->{'url'} . '/?' ) . query_string($q) ),
            'live' => $live,
            'name' => $name
        }
    );
    for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
        $p->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
    }
    $p->addScriptTag( { content => $js } );
    main::wait( $p, 'window.__test&&leqra.version==="4.4.0"' );
    evaluate_js( $p, '__test.render()' );
    return $p;
}

sub fixture {
    my ( $code, $route, $kw ) = @_;
    my ($data);
    $route //= 'arsenal44';
    $kw    //= {};
    $data = Encode::encode_utf8( json_text( { 'code' => $code } ) );
    return decode_json(
        request_ok(
            HTTP::Request->new(
                'POST',
                ( ( $a->{'url'} . '/_fixture/' ) . $route ),
                [ %{ { 'Content-Type' => 'application/json' } } ], $data
            )
        )->content
    );
}

sub dims {
    my ($p) = @_;
    return evaluate_js( $p->locator('#arenaWrap'), '(e)=>({w:e.clientWidth,h:e.clientHeight})' );
}

sub play {
    my ($p) = @_;
    $p->locator('#startRoomBtn')->click();
    evaluate_js( $p,
'()=>{__test.setPhase(\'playing\');for(const t of __test.tanks){t.human=true;t.invulnerable=600;t.vx=t.vy=0;t.angle=0;}__test.updateHUD(true);__test.render();}'
    );
}

sub rings {
    my ( $p, $n ) = @_;
    return evaluate_js(
        $p,
'n=>{const t=__test.tanks[0];t.shield=10;t.shieldCharges=n;t.invulnerable=0;const c=document.getElementById(\'arena\').getContext(\'2d\'),oldArc=c.arc,oldStroke=c.stroke,oldBegin=c.beginPath;let arc=null,got=[];c.beginPath=function(...a){arc=null;return oldBegin.apply(this,a)};c.arc=function(x,y,r,...a){arc=r;return oldArc.call(this,x,y,r,...a)};c.stroke=function(...a){if(arc>=25&&arc<=43)got.push(arc);return oldStroke.apply(this,a)};try{__test.drawTank(t)}finally{c.arc=oldArc;c.stroke=oldStroke;c.beginPath=oldBegin}return got;}',
        $n
    );
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$ok = JSON::PP::false;
eval {
    for $size ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        for $skin ( @{ [ 'dark', 'light' ] } ) {
            $p   = main::load( $b, $size, $skin );
            $tag = ( $skin . '-' . $size->[0] . 'x' . $size->[1] );
            main::check(
                (
                    value_eq(
                        evaluate_js( $p, 'leqraTheme.palette.accent' ),
                        (
                            truth_value( ( value_eq( $skin, 'dark' ) ) )
                            ? '#00c8ff'
                            : '#a100ff'
                        )
                    )
                ),
                ( $tag . ' primary accent' )
            );
            main::check( ( value_eq( $p->locator('[data-tank-color]')->count(), 4 ) ),
                ( $tag . ' four host tank palettes' ) );
            if ( truth_value( ( value_eq( $size, [ 1365, 950 ] ) ) ) ) {
                $matched = evaluate_js( $p,
'()=>[...document.querySelectorAll(\'.power-list canvas[data-power-icon]\')].map(icon=>{const c=document.createElement(\'canvas\');c.width=icon.width;c.height=icon.height;const ctx=c.getContext(\'2d\');ctx.setTransform(c.width/26,0,0,c.width/26,c.width/2,c.height/2);__test.powerIcon(icon.dataset.powerIcon,ctx);return[icon.dataset.powerIcon,c.toDataURL()===icon.toDataURL()]})'
                );
                for my $item ( @{$matched} ) {
                    my $tuple_49_9 = $item;
                    my $kind       = $tuple_49_9->[0];
                    my $equal      = $tuple_49_9->[1];
                    main::check( $equal,
                        ( ( ( $tag . ' ' ) . $kind ) . ' legend matches shared maze drawing' ) );
                }
            }
            $p->locator('[data-tank-color="0"]')->selectOption('5');
            main::check( ( value_eq( evaluate_js( $p, '__test.localRoom.players[0].colorIndex' ), 5 ) ),
                ( $tag . ' local tank color applied' ) );
            main::check( ( value_eq( $p->locator('[data-tank-color="0"] option')->count(), 9 ) ),
                ( $tag . ' eight choices plus inherit' ) );
            if ( truth_value( ( value_eq( $size, [ 1365, 950 ] ) ) ) ) {
                $p->screenshot(
                    {
                        path => format_value( $out->child( ( ( 'room-' . $skin ) . '.png' ) ) )
                    }
                );
            }
            $p->locator('#roomRulesBtn')->click();
            $p->locator('#rule-teamColor1')->selectOption('6');
            $p->locator('#rule-teamColor2')->selectOption('4');
            main::check( ( ( $p->locator('#rule-teamColor1')->boundingBox()->{'height'} <= 42 ) ),
                ( $tag . ' compact team color selector' ) );
            main::check( ( value_eq( $p->locator('#rule-teamColor1 option')->count(), 8 ) ),
                ( $tag . ' exactly eight team choices' ) );
            if ( truth_value( ( contains_value( [ [ 1365, 950 ], [ 320, 568 ] ], $size ) ) ) ) {
                $p->screenshot(
                    {
                        path => format_value( $out->child( ( ( 'rules-' . $tag ) . '.png' ) ) )
                    }
                );
            }
            $p->locator('#applyRulesBtn')->click();
            main::check( ( value_eq( evaluate_js( $p, '__test.currentRules().teamColors[0]' ), 6 ) ),
                ( $tag . ' team color saved' ) );
            $preset = evaluate_js( $p, '__test.snapshotPreset()' );
            main::check(
                (
                    do {
                        my $boolean_value = ( value_eq( $preset->{'roster'}->[0]->{'colorIndex'}, 5 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( array_slice( $preset->{'rules'}->{'teamColors'}, 0, 2 ), [ 6, 4 ] ) )
                          : $boolean_value;
                    }
                ),
                ( $tag . ' preset preserves both color choices' )
            );
            main::play($p);
            $before = main::dims($p);
            for $n ( @{ [ 1 .. 6 - 1 ] } ) {
                main::check(
                    ( value_eq( scalar( @{ main::rings( $p, $n ) } ), $n ) ),
                    ( $tag . ' exactly ' . $n . ' shield ring(s)' )
                );
            }
            evaluate_js( $p,
'()=>{const t=__test.tanks[0];t.shield=10;t.shieldCharges=5;for(const k of [\'speed\',\'scope\',\'ghost\',\'scatter\'])__test.grantPower(t,k);__test.updateHUD(true);__test.updateCombatFeedback(true);__test.render();}'
            );
            main::check( ( value_eq( main::dims($p), $before ) ),
                ( $tag . ' stacked buffs do not resize arena' ) );
            main::check( ( contains_value( $p->locator('#buffLabel')->innerText(), 'SHD×5' ) ),
                ( $tag . ' HUD shows five shields' ) );
            if ( truth_value( ( ( $size->[0] <= 390 ) ) ) ) {
                main::check( evaluate_js( $p->locator('#buffLabel'), '(e)=>e.clientWidth>=e.scrollWidth' ),
                    ( $tag . ' all compact buff badges fit without truncation' ) );
            }
            main::check( ( contains_value( $p->locator('#weaponLabel')->innerText(), 'SHOTGUN' ) ),
                ( $tag . ' Shotgun renamed in HUD' ) );
            main::check(
                (
                    do {
                        my $boolean_value =
                          ( contains_value( $p->locator('.power-list')->innerText(), 'Machine gun' ) );
                        truth_value($boolean_value)
                          ? ( !( contains_value( $p->locator('.power-list')->innerText(), 'Triple shot' ) ) )
                          : $boolean_value;
                    }
                ),
                ( $tag . ' legend names updated' )
            );
            $p->screenshot(
                {
                    path => format_value( $out->child( ( ( 'shields-' . $tag ) . '.png' ) ) )
                }
            );
            $state = evaluate_js( $p,
'JSON.stringify({x:__test.tanks[0].x,y:__test.tanks[0].y,team:__test.tanks[0].team,color:__test.tanks[0].color})'
            );
            evaluate_js( $p,
                'leqraTheme.setPreference(leqraTheme.resolved==="dark"?"light":"dark");__test.render()' );
            main::check(
                (
                    do {
                        my $boolean_value =
                          ( value_eq( main::dims($p), $before ) );
                        truth_value($boolean_value)
                          ? (
                            value_eq(
                                evaluate_js(
                                    $p,
'JSON.stringify({x:__test.tanks[0].x,y:__test.tanks[0].y,team:__test.tanks[0].team,color:__test.tanks[0].color})'
                                ),
                                $state
                            )
                          )
                          : $boolean_value;
                    }
                ),
                ( $tag . ' live appearance switch preserves physics and dimensions' )
            );
            $p->close();
        }
    }
    $p = main::load($b);
    main::play($p);
    $data = evaluate_js( $p,
'()=>{const chosen=[];const old=Math.random;try{for(let i=0;i<5;i++){Math.random=()=> (i+.1)/5;chosen.push(__test.choosePickup([\'shield\',\'rapid\',\'scatter\']))}}finally{Math.random=old}return chosen}'
    );
    main::check( ( value_eq( $data, [ 'shield', 'shield', 'shield', 'rapid', 'scatter' ] ) ),
        'JS exact shield selection weight 3:1:1' );
    $data = evaluate_js( $p,
'()=>{const t=__test.tanks[0];t.invulnerable=0;t.shield=0;t.shieldCharges=0;for(let i=0;i<8;i++)__test.grantPower(t,\'shield\');let stages=[__test.shieldCount(t)];for(let i=0;i<5;i++){t.invulnerable=0;__test.hurt(t,{owner:1});stages.push(__test.shieldCount(t));}return{stages,alive:t.alive,shield:t.shield}}'
    );
    main::check(
        (
            value_eq(
                $data,
                {
                    'stages' => [ 5, 4, 3, 2, 1, 0 ],
                    'alive'  => JSON::PP::true,
                    'shield' => 0
                }
            )
        ),
        'Local shield cap and one-charge damage agree with Go'
    );
    for my $item ( @{ [ [ 'rapid', 846, ( 3.5 / 3 ) ], [ 'scatter', 846, 3.5 ] ] } ) {
        my $tuple_78_6 = $item;
        my $power      = $tuple_78_6->[0];
        my $speed      = $tuple_78_6->[1];
        my $radius     = $tuple_78_6->[2];
        my $spec       = evaluate_js( $p, '(k)=>__test.projectileSpec(k)', $power );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( value_eq( $spec->{'speed'}, $speed ) );
                    truth_value($boolean_value)
                      ? ( ( abs( ( $spec->{'r'} - $radius ) ) < 1e-09 ) )
                      : $boolean_value;
                }
            ),
            ( $power . ' exact local size and speed' )
        );
    }
    evaluate_js( $p,
'()=>{__test.clearBullets();for(const t of __test.tanks)t.invulnerable=600;const t=__test.tanks[0];t.ghostTime=0;__test.grantPower(t,\'rapid\');window.__seen=new Set();}'
    );
    $p->keyboard()->down('f');
    evaluate_js( $p,
'()=>{for(let i=0;i<240;i++){__test.update(1/120);for(const b of __test.bullets)if(b.owner===0)__seen.add(b.id)}}'
    );
    $p->keyboard()->up('f');
    $count = evaluate_js( $p, '__seen.size' );
    main::check( ( ( 119 <= $count ) && ( $count <= 121 ) ),
        ( 'Local 120Hz physics emits Machine gun at 60Hz (' . $count . ' in 2s)' ) );
    main::check( ( ( evaluate_js( $p, '__test.bullets.filter(b=>b.owner===0).length' ) <= 91 ) ),
        'Local machine-gun lifetime bounds live rounds' );
    main::check( ( value_eq( evaluate_js( $p, '__test.tanks[0].cooldown' ), 0 ) ),
        'Local machine-gun cooldown is zero' );
    evaluate_js( $p,
'()=>{const t=__test.tanks[0];t.invulnerable=0;t.shield=10;t.shieldCharges=5;__test.hurt(t,{owner:t.id,kind:\'scatter\'});__test.updateHUD(true);__test.render()}'
    );
    main::check( ( value_eq( evaluate_js( $p, '__test.shieldCount(__test.tanks[0])' ), 5 ) ),
        'Local Shotgun self hit never consumes shield' );
    $p->close();

    if ( truth_value( ( !truth_value( $a->{'local_only'} ) ) ) ) {
        $host = main::load( $b, undef, undef, JSON::PP::true, undef, undef, 'HOST' );
        $host->locator('#addLocalBtn')->click();
        $host->locator('[data-tank-color="0"]')->selectOption('6');
        $host->locator('#copyInviteBtn')->click();
        main::wait( $host,
            '__test.online.connected&&__test.online.roomData?.players.some(p=>p.kind==="local")' );
        $code  = evaluate_js( $host, '__test.online.code' );
        $pid   = evaluate_js( $host, '__test.online.id' );
        $p2id  = evaluate_js( $host, '__test.online.roomData.players.find(p=>p.kind==="local").id' );
        $guest = main::load( $b, undef, 'light', JSON::PP::true, $code, undef, 'FRIEND' );
        main::wait( $guest, '__test.online.connected' );
        $gid    = evaluate_js( $guest, '__test.online.id' );
        $viewer = main::load( $b, [ 320, 568 ], 'light', JSON::PP::true, $code, JSON::PP::true, 'WATCHER' );
        $viewer->locator('#joinRoomBtn')->click();
        main::wait( $viewer, '__test.online.connected&&__test.online.spectating' );
        main::check(
            (
                do {
                    my $boolean_value = ( value_eq( $guest->locator('[data-tank-color]')->count(), 0 ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $viewer->locator('[data-tank-color]')->count(), 0 ) )
                      : $boolean_value;
                }
            ),
            'Guests and spectators cannot edit tank colors'
        );
        main::wait( $host, ( 'document.querySelector(\'[data-tank-color="' . $gid . '"]\')' ) );
        $host->locator( ( '[data-tank-color="' . $gid . '"]' ) )->selectOption('4');
        main::wait( $guest,
            ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').colorIndex===4' ) );
        main::check(
            (
                value_eq(
                    evaluate_js(
                        $guest, ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').color' )
                    ),
                    '#ffc46b'
                )
            ),
            'Host selection replicated as stable canonical color'
        );
        main::check(
            (
                !value_eq(
                    evaluate_js( $guest, 'leqraTheme.assetColor("#ffc46b")' ),
                    evaluate_js( $host,  'leqraTheme.assetColor("#ffc46b")' )
                )
            ),
            'Same online tank uses each viewer’s theme variant'
        );
        $guest->locator('#readyBtn')->click();
        main::wait( $host, '!document.querySelector("#startRoomBtn").disabled' );
        $host->locator('#startRoomBtn')->click();
        main::wait( $host,   '__test.phase==="playing"' );
        main::wait( $viewer, '__test.phase==="playing"' );
        $gen =
          main::fixture( $code, 'combat42', { 'action' => 'setup', 'weapon' => 'rapid' } )->{'generation'};
        main::wait( $host,   'g=>__test.online.generation===g', { 'arg' => $gen } );
        main::wait( $viewer, 'g=>__test.online.generation===g', { 'arg' => $gen } );
        main::fixture( $code, { 'action' => 'shield', 'player' => $pid,  'count' => 7 } );
        main::fixture( $code, { 'action' => 'shield', 'player' => $p2id, 'count' => 3 } );
        main::wait( $host, ( '__test.online.snapshots.at(-1).tankMap.get(' . $pid . ').shieldCharges===5' ) );
        main::check(
            (
                value_eq(
                    evaluate_js(
                        $host, ( '__test.online.snapshots.at(-1).tankMap.get(' . $p2id . ').shieldCharges' )
                    ),
                    3
                )
            ),
            'Go independently stacks both local pilots'
        );
        main::wait( $viewer,
            ( '__test.online.snapshots.at(-1).tankMap.get(' . $pid . ').shieldCharges===5' ) );
        main::check( JSON::PP::true, 'Spectator receives authoritative shield charges' );
        main::fixture( $code, { 'action' => 'hit', 'player' => $pid } );
        main::wait( $host, ( '__test.online.snapshots.at(-1).tankMap.get(' . $pid . ').shieldCharges===4' ) );
        main::check( JSON::PP::true, 'Online shield hit consumes exactly one charge' );
        $before = main::dims($host);
        $host->keyboard()->down('f');
        $host->keyboard()->down('Space');
        $Leqra::Browser::HANDLE->await( $host->waitForTimeout(1350) );
        $host->keyboard()->up('f');
        $host->keyboard()->up('Space');
        $Leqra::Browser::HANDLE->await( $host->waitForTimeout(120) );
        $counts = evaluate_js(
            $host,
            'ids=>ids.map(id=>__test.online.snapshots.at(-1).tankMap.get(id).shotSerial)',
            [ $pid, $p2id ]
        );
        main::check( ( ( min( @{$counts} ) >= 60 ) ),
            ( 'Both online machine guns sustain continuous fire: ' . format_value($counts) ) );
        $raw = evaluate_js( $host, '__lastRaw' );
        main::check(
            ( ( scalar( @{ ( $raw->{'machineBullets'} // [] ) } ) > 20 ) ),
            'Server uses compact high-rate machine-gun snapshots'
        );
        main::check(
            (
                (
                    evaluate_js( $host,
'__test.online.snapshots.at(-1).bullets.filter(b=>b.kind==="rapid"&&Math.abs(b.r-3.5/3)<1e-9).length'
                    ) > 20
                )
            ),
            'Browser expands compact shots with correct geometry'
        );
        main::check( ( ( evaluate_js( $host, '__test.presentationMetrics.previews' ) > 30 ) ),
            'Machine gun retains immediate local previews' );
        main::check( ( value_eq( main::dims($host), $before ) ),
            'Online stream and shield hits do not change arena size' );
        main::check( ( value_eq( $host->locator('#cooldownText1')->innerText(), 'READY' ) ),
            'Continuous-fire feedback has no false cooldown' );
        main::check(
            (
                do {
                    my $boolean_value = $host->locator('#machineBudget1')->isVisible();
                    truth_value($boolean_value)
                      ? ( index( $host->locator('#machineBudget1')->innerText(), 'FIRE ' ) == 0 )
                      : $boolean_value;
                }
            ),
            'Remaining machine-gun firing time appears beside ammo'
        );
        $host->screenshot( { path => format_value( $out->child('online-stream-dark.png') ) } );
        $viewer->screenshot(
            {
                path => format_value( $out->child('online-shields-light-320.png') )
            }
        );
        $gen =
          main::fixture( $code, 'combat42', { 'action' => 'setup', 'weapon' => 'scatter' } )->{'generation'};
        main::wait( $host, 'g=>__test.online.generation===g', { 'arg' => $gen } );
        $host->keyboard()->press('f');
        $host->keyboard()->press('Space');
        $Leqra::Browser::HANDLE->await( $host->waitForTimeout(180) );
        $pellets = evaluate_js(
            $host,
            '(ids)=>__test.online.snapshots.at(-1).bullets.filter(b=>ids.includes(b.owner))',
            [ $pid, $p2id ]
        );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( value_eq( scalar( @{$pellets} ), 6 ) );
                    truth_value($boolean_value)
                      ? !scalar(
                        grep {
                            my $b = $_;
                            !(
                                (
                                    do {
                                        my $boolean_value = ( value_eq( $b->{'kind'}, 'scatter' ) );
                                        truth_value($boolean_value)
                                          ? (
                                            (
                                                abs(
                                                    (
                                                        ( ( ( $b->{'vx'}**2 ) + ( $b->{'vy'}**2 ) )**0.5 ) -
                                                          846
                                                    )
                                                ) < 0.02
                                            )
                                          )
                                          : $boolean_value;
                                    }
                                )
                            )
                        } @{$pellets}
                      )
                      : $boolean_value;
                }
            ),
            'Both local online Shotguns emit three high-speed pellets'
        );
        $token = evaluate_js( $host, '__test.online.token' );
        evaluate_js( $host, '__test.online.socket.close(4000,"regression")' );
        main::wait( $host, '!__test.online.connected' );
        main::wait( $host, '__test.online.connected', { 'timeout' => 15000 } );
        main::check( ( value_eq( evaluate_js( $host, '__test.online.token' ), $token ) ),
            'Reconnect retains both pilots and palette identity' );
        main::check(
            (
                value_eq(
                    evaluate_js(
                        $host, '__test.online.roomData.players.find(p=>p.id===__test.online.id).colorIndex'
                    ),
                    6
                )
            ),
            'Selected tank color survives reconnect'
        );
        main::fixture( $code, 'combat42', { 'action' => 'win', 'player' => $pid } );
        main::wait( $host, '__test.phase==="matchOver"', { 'timeout' => 12000 } );
        main::wait( $viewer, '__test.phase==="matchOver"' );
        main::check( ( value_eq( $host->locator('#cooldownText1')->innerText(), 'MATCH COMPLETE' ) ),
            'Victory feedback remains stable with new weapons' );
        $viewer->screenshot( { path => format_value( $out->child('victory-light.png') ) } );
    }
    main::check( ( !truth_value($errors) ), ( 'No uncaught browser errors: ' . format_value($errors) ) );
    $ok = JSON::PP::true;
    1;
};
my $caught_error = $@;
for $c ( @{$contexts} ) {
    $c->close();
}
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'   => '4.4.0',
            'completed' => $ok,
            'passed'    => scalar( @{$checks} ),
            'checks'    => $checks,
            'errors'    => $errors
        },
        1
    )
);
die $caught_error if $caught_error;
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
