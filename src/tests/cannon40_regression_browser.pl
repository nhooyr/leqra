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
    $ap, $args, $assets, $b,      $c,    $checks, $ctx, $dt,  $errors, $ff,
    $h,  $html, $i,      $icons,  $js,   $mobile, $out, $p,   $page,   $pw,
    $q,  $r,    $report, $result, $root, $stored, $w,   $web, $x
);

# Cannon v3.9: exact shipped browser assets, deterministic local stepping.
# No network mocks alter collision, damage, bots, guides, or rendering.
$ap   = {};
$args = do {
    my %args = (
        'output'  => 'test-output/cannon39',
        'browser' => '/usr/bin/chromium'
    );
    my $help;
    GetOptions(
        'output=s'  => \$args{'output'},
        'browser=s' => \$args{'browser'},
        'help|h'    => \$help
      )
      or die 'Usage: perl cannon40_regression_browser.pl --output --browser
';
    if ($help) {
        print 'Usage: perl cannon40_regression_browser.pl --output --browser
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
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}
$html = replace_re( '<link[^>]*>',                         '', $web->child('index.html')->slurp_utf8 );
$html = replace_re( '<script src="[^"]+" defer></script>', '', $html );
$html = replace_text( $html, '</head>',
    ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' ) );
$js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
$i  = rindex( $js, '})()' );
$js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location);' ) . substr( $js, ( $i + 4 ) ) );

sub load {
    my ( $c, $data ) = @_;
    my ($p);
    $data //= undef;
    $p = $c->newPage();
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->setContent($html);
    evaluate_js(
        $p,
        'data=>{window.__location=new URL(\'http://game.test/?test=1\');window.__store=data;
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,\'localStorage\',{value:store(data)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});window.requestAnimationFrame=()=>0;}',
        (
            do {
                my $boolean_value = $data;
                truth_value($boolean_value)
                  ? $boolean_value
                  : { 'leqra.muted' => '1' };
            }
        )
    );
    $p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.__test' );
    evaluate_js(
        $p,
        '()=>{window.arena39=(n=3,wall=true)=>{const T=__test;T.setPhase(\'menu\');
 T.applyLocalPreset({rules:{...T.defaultRoomRules(),teamMode:\'ffa\',pickupRate:\'off\'},roster:Array.from({length:n},(_,i)=>({kind:i===0?\'human\':i===1?\'local\':\'bot\',name:\'P\'+i,team:0,difficulty:\'normal\'}))});T.startRound();T.setPhase(\'playing\');T.clearInput();T.clearBullets();
 T.setWorld({width:1008,height:840,cols:12,rows:10,walls:[{x:-4,y:-4,w:1016,h:8,axis:\'h\',line:0},{x:-4,y:836,w:1016,h:8,axis:\'h\',line:840},{x:-4,y:-4,w:8,h:848,axis:\'v\',line:0},{x:1004,y:-4,w:8,h:848,axis:\'v\',line:1008},...(wall?[{x:142,y:-4,w:8,h:848,axis:\'v\',line:146},{x:230,y:-4,w:32,h:848,axis:\'v\',line:246}]:[])]});
 T.tanks.forEach((t,i)=>Object.assign(t,{human:true,x:80+i*120,y:210+i*70,angle:0,alive:true,invulnerable:0,cooldown:0,power:null,powerTime:0,charges:0,shield:0,speedTime:0,scopeTime:0,team:0}));return T;};}'
    );
    return $p;
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => $args->{'browser'}
);
eval {
    $c = $b->newContext( { viewport => { 'width' => 1365, 'height' => 950 } } );
    $p = main::load($c);
    main::check( ( value_eq( evaluate_js( $p, 'leqra.version' ), '4.0.0' ) ), 'Version 4.0.0 loads' );
    main::check(
        evaluate_js(
            $p,
            'leqra.getState().rules.weapons.length===9 && leqra.getState().rules.weapons.includes(\'cannon\')'
        ),
        'Cannon included among nine default pickups'
    );
    $p->locator('#roomRulesBtn')->click();
    main::check( $p->locator('[data-weapon-toggle="cannon"]')->isChecked(),
        'Cannon host rule toggle starts enabled' );
    $p->locator('[data-weapon-toggle="cannon"]')->uncheck();
    $p->locator('#applyRulesBtn')->click();
    main::check( evaluate_js( $p, '!leqra.getState().rules.weapons.includes(\'cannon\')' ),
        'Host can disable Cannon' );
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetName')->fill('No Cannon');
    $p->locator('#savePresetBtn')->click();
    $stored = evaluate_js( $p, '__store' );
    $p->locator('[data-close-dialog="presetsDialog"]')->click();
    $q = main::load( $c, $stored );
    $q->locator('#roomPresetsBtn')->click();
    $q->locator('#presetSelect')->selectOption('saved:0');
    $q->locator('#loadPresetBtn')->click();
    main::check(
        evaluate_js( $q, '!leqra.getState().rules.weapons.includes(\'cannon\')' ),
        'Saved explicit weapon list stays unchanged after reload'
    );
    $q->close();
    $r = evaluate_js(
        $p,
'()=>{const T=arena39(),p=T.tanks[0];const a=T.projectileSpec(null),s=T.projectileSpec(\'cannon\');T.grantPower(p,\'scope\');T.grantPower(p,\'speed\');T.grantPower(p,\'shield\');T.grantPower(p,\'cannon\');
   const grants={power:p.power,charges:p.charges,time:p.powerTime,scope:p.scopeTime,speed:p.speedTime,shield:p.shield};T.fire(p);const b=T.bullets[0],first={r:b.r,vx:b.vx,kind:b.kind,x:b.x,cooldown:p.cooldown,charges:p.charges};const repeated=T.fire(p);T.updateBullets(.4);return{a,s,grants,first,repeated,after:{x:b.x,vx:b.vx,bounces:b.bounces,dead:b.dead}};}'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( $r->{'s'}->{'r'}, ( 3 * $r->{'a'}->{'r'} ) ) );
                truth_value($boolean_value)
                  ? ( value_eq( $r->{'s'}->{'speed'}, ( 3 * $r->{'a'}->{'speed'} ) ) )
                  : $boolean_value;
            }
        ),
        'Cannon diameter and speed exactly three times a standard shot'
    );
    main::check(
        (
            value_eq(
                $r->{'grants'},
                {
                    'power'   => 'cannon',
                    'charges' => 3,
                    'time'    => 10,
                    'scope'   => 10,
                    'speed'   => 6,
                    'shield'  => 10
                }
            )
        ),
        'Cannon grants three shots/ten seconds and preserves independent buffs'
    );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( $r->{'repeated'} ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( $r->{'first'}->{'cooldown'}, 0.85 ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $r->{'first'}->{'charges'}, 2 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Cannon cooldown prevents duplicate held-frame firing'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( ( abs( ( ( $r->{'after'}->{'x'} - $r->{'first'}->{'x'} ) - ( 0.4 * 846 ) ) ) < 1e-06 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( $r->{'after'}->{'vx'}, 846 ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value =
                          ( value_eq( $r->{'after'}->{'bounces'}, 0 ) );
                        truth_value($boolean_value)
                          ? ( !truth_value( $r->{'after'}->{'dead'} ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Actual local shot crosses two walls without speed loss or bouncing'
    );
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0];p.x=117;T.grantPower(p,\'cannon\');const b=T.muzzleProjectile(p,0);return{x:b.x,vx:b.vx,bounces:b.bounces,inside:b.x>=142&&b.x<=150};}'
    );
    main::check(
        (
            do {
                my $boolean_value = $r->{'inside'};
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( value_eq( $r->{'x'}, 145 ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( $r->{'vx'}, 846 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $r->{'bounces'}, 0 ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Wall-overlapping muzzle does not reflect or relocate Cannon shot'
    );
    for $dt ( @{ [ ( 1 / 120 ), ( 1 / 60 ), 0.05, 0.5 ] } ) {
        $r = evaluate_js(
            $p,
'dt=>{const T=arena39(),p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];a.x=320;a.y=210;b.x=420;b.y=210;T.grantPower(p,\'cannon\');T.fire(p);const shot=T.bullets[0];for(let time=0;time<.5-1e-9;){const s=Math.min(dt,.5-time);T.updateBullets(s);time+=s;}return{target:a.alive,behind:b.alive,x:shot.x,dead:shot.dead,count:T.bullets.length};}',
            $dt
        );
        main::check(
            (
                do {
                    my $boolean_value = ( !truth_value( $r->{'target'} ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = $r->{'behind'};
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value = $r->{'dead'};
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value =
                                  ( value_eq( $r->{'count'}, 0 ) );
                                truth_value($boolean_value)
                                  ? ( ( abs( ( $r->{'x'} - 292.5 ) ) < 1e-06 ) )
                                  : $boolean_value;
                              }
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( 'Swept first-tank hit at timestep ' . $dt . '; no tank piercing' )
        );
    }
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];a.x=320;a.y=210;a.shield=10;b.x=325;b.y=245;T.grantPower(p,\'cannon\');T.fire(p);T.updateBullets(.5);return{alive:a.alive,shield:a.shield,other:b.alive,count:T.bullets.length};}'
    );
    main::check(
        (
            value_eq(
                $r,
                {
                    'alive'  => JSON::PP::true,
                    'shield' => 0,
                    'other'  => JSON::PP::true,
                    'count'  => 0
                }
            )
        ),
        'Shield absorbs one Cannon hit; no area damage'
    );
    for $ff ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
        $r = evaluate_js(
            $p,
'ff=>{const T=arena39();T.localRoom.rules.teamMode=\'teams\';T.localRoom.rules.friendlyFire=ff;const p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];p.team=a.team=2;b.team=3;a.x=220;a.y=210;a.shield=10;b.x=370;b.y=210;T.grantPower(p,\'cannon\');T.fire(p);T.updateBullets(.5);return{a:a.alive,shield:a.shield,b:b.alive};}',
            $ff
        );
        main::check(
            (
                do {
                    my $boolean_value = $r->{'a'};
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( $r->{'shield'}, ( truth_value($ff) ? 0 : 10 ) ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $r->{'b'}, $ff ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( 'Friendly fire ' . $ff . ': correct ally shield and downstream enemy handling' )
        );
    }
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0];T.grantPower(p,\'cannon\');const fired=[];for(let i=0;i<3;i++){p.cooldown=0;fired.push(T.fire(p));}const out={fired,power:p.power,charges:p.charges,time:p.powerTime,kinds:T.bullets.map(b=>b.kind)};T.clearBullets();p.power=\'cannon\';p.charges=0;p.cooldown=0;out.empty=T.fire(p);T.grantPower(p,\'cannon\');p.powerTime=.001;T.update(1/120);out.expired=!p.power;return out;}'
    );
    main::check(
        (
            do {
                my $boolean_value = ( !grep { !$_ } @{ $r->{'fired'} } );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( !defined( $r->{'power'} ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( $r->{'charges'}, 0 ) );
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value = ( value_eq( $r->{'time'}, 0 ) );
                            truth_value($boolean_value)
                              ? ( value_eq( $r->{'kinds'}, ( ['cannon'] * 3 ) ) )
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Final charge resets weapon, not existing Cannon shots'
    );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( $r->{'empty'} ) );
                truth_value($boolean_value) ? $r->{'expired'} : $boolean_value;
            }
        ),
        'Zero-charge shots refused; equip timer expires'
    );
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0];for(const e of T.tanks.slice(1))e.alive=false;T.grantPower(p,\'cannon\');T.fire(p);const b=T.bullets[0];for(let i=0;i<600;i++)T.updateBullets(1/60);const exited=b.dead&&T.bullets.length===0&&b.bounces===0;T.grantPower(p,\'cannon\');p.cooldown=0;T.fire(p);const short=T.bullets[0],x=short.x;short.life=.002;T.updateBullets(.1);return{exited,expired:short.dead,dx:short.x-x};}'
    );
    main::check(
        (
            do {
                my $boolean_value = $r->{'exited'};
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = $r->{'expired'};
                    truth_value($boolean_value)
                      ? ( ( abs( ( $r->{'dx'} - ( 0.002 * 846 ) ) ) < 1e-06 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Arena exit and fractional lifetime bound Cannon shots'
    );
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0];T.tanks.slice(1).forEach(t=>t.alive=false);T.grantPower(p,\'cannon\');const b=T.muzzleProjectile(p,0),before=JSON.stringify(b),visual=T.projectOnlineBullet(b,.12),unchanged=JSON.stringify(b)===before;T.bullets.push({...b,id:1,trail:[]});T.updateBullets(.12);return{dx:visual.x-b.x,local:T.bullets[0].x,visual:visual.x,vx:visual.vx,bounces:visual.bounces,unchanged};}'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( ( abs( ( $r->{'dx'} - ( 0.12 * 846 ) ) ) < 1e-06 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( ( abs( ( $r->{'local'} - $r->{'visual'} ) ) < 1e-06 ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( $r->{'vx'}, 846 ) );
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value =
                              ( value_eq( $r->{'bounces'}, 0 ) );
                            truth_value($boolean_value)
                              ? $r->{'unchanged'}
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Online visual extrapolation crosses walls and matches simulation without mutating snapshots'
    );
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0],e=T.tanks[1];T.tanks[2].alive=false;e.x=320;e.y=210;T.grantPower(p,\'cannon\');const d={lead:1};const aim=T.evaluateBotShot(p,0,e,d,0);T.fire(p);const threats=T.forecastThreats(e,.65);return{hit:aim?.target,flight:aim?.flight,bounces:aim?.bounces,threats:threats.map(t=>({r:t.r,x:t.x,dx:t.vx*(t.end-t.start)}))};}'
    );
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( $r->{'hit'}, 1 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( ( $r->{'flight'} < 0.3 ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $r->{'bounces'}, 0 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Local bots aim through walls with Cannon intercept timing'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( scalar( @{ $r->{'threats'} } ), 1 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( $r->{'threats'}->[0]->{'r'}, 10.5 ) );
                    truth_value($boolean_value)
                      ? ( ( $r->{'threats'}->[0]->{'dx'} > 400 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Bot dodge forecast treats Cannon as a large, fast wall-piercing threat'
    );
    $r = evaluate_js( $p,
'()=>{const T=arena39(),p=T.tanks[0];T.tanks.slice(1).forEach(t=>t.alive=false);T.grantPower(p,\'cannon\');const short=T.aimingGuide(p);p.scopeTime=10;const long=T.aimingGuide(p);const e=T.tanks[1];e.x=320;e.y=210;e.alive=true;const stop=T.aimingGuide(p);p.power=null;p.scopeTime=0;const regular=T.aimingGuide(p);return{short,long,end:stop.points.at(-1),target:stop.tank?.id,regular:regular.points};}'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( scalar( @{ $r->{'short'}->{'points'} } ), 2 ) );
                truth_value($boolean_value)
                  ? ( value_eq( $r->{'short'}->{'points'}->[ (-1) ]->{'x'}, 192 ) )
                  : $boolean_value;
            }
        ),
        'Normal Cannon guide crosses nearby wall instead of suggesting a bounce'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( scalar( @{ $r->{'long'}->{'points'} } ), 2 ) );
                truth_value($boolean_value)
                  ? ( value_eq( $r->{'long'}->{'points'}->[ (-1) ]->{'x'}, 1008 ) )
                  : $boolean_value;
            }
        ),
        'Scoped Cannon guide stays straight, ends at arena edge, and remains range-bounded'
    );
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( $r->{'target'}, 1 ) );
                truth_value($boolean_value)
                  ? ( ( abs( ( $r->{'end'}->{'x'} - 292.5 ) ) < 1e-06 ) )
                  : $boolean_value;
            }
        ),
        'Cannon guide uses enlarged projectile contact radius'
    );
    main::check( ( ( scalar( @{ $r->{'regular'} } ) > 2 ) ),
        'Ordinary short guide still reflects from walls' );
    $r = evaluate_js( $p,
'()=>{const T=arena39();T.pickups.length=0;const p=T.tanks[0];T.pickups.push({x:p.x,y:p.y,type:\'cannon\',age:0,life:19});T.update(1/120);return{power:p.power,charges:p.charges,time:p.powerTime,pickups:T.pickups.length};}'
    );
    main::check(
        (
            value_eq(
                $r,
                {
                    'power'   => 'cannon',
                    'charges' => 3,
                    'time'    => 10,
                    'pickups' => 0
                }
            )
        ),
        'Driving over a real Cannon pickup collects it and removes it from the maze'
    );
    evaluate_js( $p,
'()=>{const T=arena39();T.tanks.slice(2).forEach(t=>t.alive=false);for(const t of T.tanks.slice(0,2)){t.invulnerable=999;T.grantPower(t,\'cannon\');}}'
    );
    $p->keyboard()->down('f');
    evaluate_js( $p, '__test.update(1/120)' );
    $p->keyboard()->up('f');
    $p->keyboard()->down('Space');
    evaluate_js( $p, '__test.update(1/120)' );
    $p->keyboard()->up('Space');
    main::check(
        evaluate_js(
            $p, '__test.bullets.filter(b=>b.kind===\'cannon\').map(b=>b.owner).sort().join(\',\')===\'0,1\''
        ),
        'F and Space independently fire primary and secondary Cannons'
    );

    for my $item ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        my $tuple_76_6 = $item;
        my $w          = $tuple_76_6->[0];
        my $h          = $tuple_76_6->[1];
        my $mobile     = (
            do {
                my $boolean_value = ( ( $w < 760 ) );
                truth_value($boolean_value) ? $boolean_value : ( ( $h < 620 ) );
            }
        );
        my $ctx = $b->newContext(
            {
                viewport          => { 'width' => $w, 'height' => $h },
                hasTouch          => $mobile,
                isMobile          => $mobile,
                deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 )
            }
        );
        my $page  = main::load($ctx);
        my $icons = evaluate_js( $page,
'()=>{__test.renderPowerLegend();return [...document.querySelectorAll(\'.power-list canvas[data-power-icon]\')].map(e=>{const f=document.createElement(\'canvas\');f.width=e.width;f.height=e.height;const c=f.getContext(\'2d\');c.setTransform(f.width/26,0,0,f.height/26,f.width/2,f.height/2);__test.powerIcon(e.dataset.powerIcon,c);return{kind:e.dataset.powerIcon,equal:e.toDataURL()===f.toDataURL()};});}'
        );
        main::check(
            (
                do {
                    my $boolean_value = ( value_eq( scalar( @{$icons} ), 9 ) );
                    truth_value($boolean_value)
                      ? !scalar( grep { my $x = $_; !( $x->{'equal'} ) } @{$icons} )
                      : $boolean_value;
                }
            ),
            ( $w . 'x' . $h . ': all nine legend icons pixel-match the pickup renderer' )
        );
        $page->locator('#roomRulesBtn')->click();
        main::check(
            $page->locator('[data-weapon-toggle="cannon"]')->isChecked(),
            ( $w . 'x' . $h . ': Cannon available in rules' )
        );
        $page->screenshot(
            {
                path => format_value( $out->child( ( 'rules-' . $w . 'x' . $h . '.png' ) ) )
            }
        );
        $page->locator('#applyRulesBtn')->click();
        evaluate_js( $page, '__test.addRoomSeat(\'local\')' );
        $page->locator('#startRoomBtn')->click();
        my $result = evaluate_js(
            $page,
'()=>{const T=__test;T.setPhase(\'playing\');T.tanks.forEach(t=>{t.human=true;t.invulnerable=999});T.clearBullets();T.updateHUD(true);T.updateCombatFeedback(true);const rect=()=>{const r=document.querySelector(\'#arenaWrap\').getBoundingClientRect();return[r.width,r.height]};const before=rect();
    const p=T.tanks.find(t=>t.id===T.localRoom.self),two=T.tanks.find(t=>t.localIndex===1);for(const t of [p,two]){T.grantPower(t,\'cannon\');T.grantPower(t,\'scope\');T.grantPower(t,\'speed\');T.grantPower(t,\'shield\');t.cooldown=0;T.fire(t);}T.updateBullets(.03);T.updateHUD(true);T.updateCombatFeedback(true);T.render();return{before,after:rect(),one:document.querySelector(\'#weaponLabel\').textContent,two:document.querySelector(\'#weaponLabel2\').textContent,body:document.body.scrollWidth,width:innerWidth};}'
        );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( value_eq( $result->{'before'}, $result->{'after'} ) );
                    truth_value($boolean_value)
                      ? ( ( $result->{'body'} <= ( $result->{'width'} + 1 ) ) )
                      : $boolean_value;
                }
            ),
            ( $w . 'x' . $h . ': Cannon/buffs do not resize maze or overflow horizontally' )
        );
        main::check(
            (
                do {
                    my $boolean_value =
                      ( contains_value( $result->{'one'}, 'CANNON' ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value =
                          ( contains_value( $result->{'one'}, '×2' ) );
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value =
                              ( contains_value( $result->{'two'}, 'CANNON' ) );
                            truth_value($boolean_value)
                              ? ( contains_value( $result->{'two'}, '×2' ) )
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                }
            ),
            ( $w . 'x' . $h . ': independent named Cannon charge/cooldown HUDs' )
        );
        $page->screenshot(
            {
                path => format_value( $out->child( ( 'cannon-' . $w . 'x' . $h . '.png' ) ) )
            }
        );
        $ctx->close();
    }
    main::check( ( !truth_value($errors) ), 'No uncaught browser errors' );
    $report = {
        'version' => '4.0.0',
        'passed'  => scalar( @{$checks} ),
        'checks'  => $checks,
        'errors'  => $errors,
        'limits'  =>
'Chromium desktop/mobile emulation; real assets, synthetic URL/storage and deterministic stepping. No physical phones.'
    };
    $out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
    print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
    1;
};
my $caught_error = $@;
$b->close();
die $caught_error if $caught_error;
