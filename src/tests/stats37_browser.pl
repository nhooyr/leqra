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
    $a,    $ap,       $args,   $assets,   $b,      $before, $browser, $c,    $checks,
    $code, $contexts, $errors, $expected, $guest,  $host,   $i,       $late, $mode,
    $out,  $p,        $page,   $pages,    $pg,     $pw,     $report,  $root, $saved,
    $size, $sockets,  $suffix, $v,        $viewer, $web,    $x
);

# v3.7: local gameplay + authoritative online results, exact shipped assets.
# Chromium uses synthetic Location/History/storage adapters and a loopback fixture.
$ap   = {};
$args = do {
    my %args = (
        'url'     => 'http://127.0.0.1:8878',
        'output'  => 'test-output/stats37',
        'browser' => '/usr/bin/chromium'
    );
    my $help;
    GetOptions(
        'url=s'     => \$args{'url'},
        'output=s'  => \$args{'output'},
        'browser=s' => \$args{'browser'},
        'help|h'    => \$help
      )
      or die 'Usage: perl stats37_browser.pl --url --output --browser
';
    if ($help) {
        print 'Usage: perl stats37_browser.pl --url --output --browser
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
    if ( truth_value( ( !truth_value($ok) ) ) ) {
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
$pages    = [];

sub load {
    my ( $name, $size, $code, $watch ) = @_;
    my ( $context, $html, $i, $js, $mobile, $p, $url );
    $name  //= 'HOST';
    $size  //= [ 1365, 950 ];
    $code  //= undef;
    $watch //= JSON::PP::false;
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
    push( @{$pages}, $p );
    $p->setDefaultTimeout(8000);
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
'([url,ws,name])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener(\'message\',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store={\'leqra.name\':name,\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:store(__store)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});history.replaceState=(s,t,u)=>{__location.href=String(u)};Object.defineProperty(navigator,\'clipboard\',{value:{writeText:async v=>{}}});}',
        [ $url, ( replace_text( $args->{'url'}, 'http:', 'ws:' ) . '/ws' ), $name ]
    );
    $js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
    $i  = rindex( $js, '})()' );
    $js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location);' ) . substr( $js, ( $i + 4 ) ) );
    $p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.leqra' );
    return $p;
}

sub setup {
    my ( $p, $mode, $count, $ff ) = @_;
    $mode  //= 'elimination';
    $count //= 8;
    $ff    //= JSON::PP::false;
    evaluate_js(
        $p,
'({mode,count,ff})=>{__test.closeVictory();const T=__test,rules={...T.defaultRoomRules(),mode,teamMode:mode===\'elimination\'?\'ffa\':\'teams\',scoreTarget:mode===\'koth\'?60:1,timeLimit:600,pickupRate:\'off\',friendlyFire:ff,teamNames:[\'Aurora 🌟\',\'Red Foxes\',\'Tidal & Co\',\'Violet Guard\']};const roster=Array.from({length:count},(_,i)=>({name:i===0?\'PILOT ONE\':i===1?\'PLAYER TWO\':[\'RUST\',\'VAPOR\',\'EMBER\',\'PIXEL\',\'NOVA\',\'COMET\'][i-2],kind:i===0?\'human\':i===1?\'local\':\'bot\',team:rules.teamMode===\'ffa\'?0:i<2?1:2,...(i>1?{difficulty:\'normal\'}:{})}));T.applyLocalPreset({rules,roster});}',
        { 'mode' => $mode, 'count' => $count, 'ff' => $ff }
    );
}

sub start {
    my ($p) = @_;
    $p->locator('#startRoomBtn')->click();
    evaluate_js( $p,
'()=>{const T=__test;T.setPhase(\'playing\');T.setWorld({width:1008,height:840,cols:12,rows:10,walls:[]});T.clearBullets();T.tanks.forEach((t,i)=>{t.human=true;t.invulnerable=0;t.x=100+i*90;t.y=300;t.cooldown=999;});}'
    );
}

sub local_finish {
    my ( $p, $mode ) = @_;
    return evaluate_js(
        $p,
'mode=>{const T=__test,t=T.tanks;T.setPhase(\'playing\');T.clearBullets();const kill=(victim,owner)=>{t[victim].alive=true;t[victim].shield=0;t[victim].invulnerable=0;T.hurt(t[victim],{owner,kind:\'grenade\'});};kill(2,0);kill(3,0);kill(4,1);kill(5,5);kill(6,0);t[7].shield=2;T.hurt(t[7],{owner:0});
   if(mode===\'ctf\'){const o=T.localObjectives,own=o.flags[0],enemy=o.flags[1];t[1].x=250;t[1].y=200;Object.assign(own,{home:false,carrier:-1,x:250,y:200,returnIn:12});T.stepLocalObjectives(1/60);t[0].x=own.homeX;t[0].y=own.homeY;Object.assign(enemy,{home:false,carrier:0,x:t[0].x,y:t[0].y,returnIn:0});T.stepLocalObjectives(1/60);}
   else if(mode===\'koth\'){const o=T.localObjectives;t[0].x=o.hillX-10;t[0].y=o.hillY;t[1].x=o.hillX+10;t[1].y=o.hillY;for(let n=0;n<135;n++)T.stepLocalObjectives(1/60);T.finishMatch(0);}
   else T.finishMatch(0);
   return leqra.getState().matchStats;
  }', $mode
    );
}

sub bounds {
    my ($p) = @_;
    return evaluate_js( $p,
'()=>{const d=document.querySelector(\'#victoryDialog\'),r=d.getBoundingClientRect(),footer=document.querySelector(\'#victoryCloseBtn\').getBoundingClientRect();return {ok:r.left>=0&&r.right<=innerWidth+1&&r.top>=0&&r.bottom<=innerHeight+1,overflow:d.scrollWidth>d.clientWidth+1,scroll:d.scrollTop,focus:document.activeElement.id,button:footer.bottom<=innerHeight+1&&footer.top>=0,bodyOverflow:document.documentElement.scrollWidth>innerWidth};}'
    );
}
eval {
    for $size ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        for $mode ( @{ [ 'elimination', 'ctf', 'koth' ] } ) {
            $p = main::load( undef, $size, undef, undef );
            main::setup( $p, $mode );
            main::start($p);
            $report = main::local_finish( $p, $mode );
            $suffix = ( ( $mode . ' ' ) . format_value($size) );
            wait_js( $p, 'document.querySelector("#victoryDialog").open' );
            main::check( ( value_eq( scalar( @{ $report->{'players'} } ), 8 ) ),
                ( 'Eight individual results ' . $suffix ) );
            $a = $report->{'players'};
            main::check(
                (
                    do {
                        my $boolean_value =
                          ( value_eq( $a->[0]->{'eliminations'}, 3 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $a->[1]->{'eliminations'}, 1 ) )
                          : $boolean_value;
                    }
                ),
                ( 'Eliminations attributed to both local players ' . $suffix )
            );
            main::check(
                (
                    do {
                        my $boolean_value =
                          ( value_eq( $a->[5]->{'selfDestructs'}, 1 ) );
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value =
                              ( value_eq( $a->[5]->{'deaths'}, 1 ) );
                            truth_value($boolean_value)
                              ? ( value_eq( $a->[5]->{'eliminations'}, 0 ) )
                              : $boolean_value;
                          }
                          : $boolean_value;
                    }
                ),
                ( 'Self-destruct separate from eliminations ' . $suffix )
            );
            main::check( ( value_eq( $a->[7]->{'deaths'}, 0 ) ),
                ( 'Shield absorption not a death ' . $suffix ) );
            main::check( ( value_eq( $p->locator('#victoryStats tbody tr')->count(), 8 ) ),
                ( 'Eight rendered result rows ' . $suffix ) );
            if ( truth_value( ( value_eq( $mode, 'ctf' ) ) ) ) {
                main::check(
                    (
                        do {
                            my $boolean_value =
                              ( value_eq( $a->[0]->{'captures'}, 1 ) );
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value =
                                  ( value_eq( $a->[1]->{'captures'}, 0 ) );
                                truth_value($boolean_value)
                                  ? ( value_eq( $a->[1]->{'flagReturns'}, 1 ) )
                                  : $boolean_value;
                              }
                              : $boolean_value;
                        }
                    ),
                    ( 'Winning capture and manual return credited personally ' . $suffix )
                );
            }
            if ( truth_value( ( value_eq( $mode, 'koth' ) ) ) ) {
                main::check(
                    (
                        do {
                            my $boolean_value =
                              ( value_eq( $a->[0]->{'hillSeconds'}, 2.25 ) );
                            truth_value($boolean_value)
                              ? ( value_eq( $a->[1]->{'hillSeconds'}, 2.25 ) )
                              : $boolean_value;
                        }
                    ),
                    ( 'Each ally gets uncontested hill time ' . $suffix )
                );
            }
            main::check(
                (
                    do {
                        my $boolean_value = (
                            value_eq(
                                $p->locator('[data-metric="captures"]')->count(),
                                (
                                    truth_value( ( value_eq( $mode, 'ctf' ) ) )
                                    ? 8
                                    : 0
                                )
                            )
                        );
                        truth_value($boolean_value)
                          ? (
                            value_eq(
                                $p->locator('[data-metric="hillSeconds"]')->count(),
                                ( truth_value( ( value_eq( $mode, 'koth' ) ) ) ? 8 : 0 )
                            )
                          )
                          : $boolean_value;
                    }
                ),
                ( 'Mode-specific columns ' . $suffix )
            );
            $b = main::bounds($p);
            main::check(
                (
                    do {
                        my $boolean_value = $b->{'ok'};
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value =
                              ( !truth_value( $b->{'overflow'} ) );
                            truth_value($boolean_value)
                              ? ( !truth_value( $b->{'bodyOverflow'} ) )
                              : $boolean_value;
                          }
                          : $boolean_value;
                    }
                ),
                ( 'Popup and page stay within viewport ' . $suffix )
            );
            main::check(
                (
                    do {
                        my $boolean_value = ( value_eq( $b->{'scroll'}, 0 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $b->{'focus'}, 'victoryTitle' ) )
                          : $boolean_value;
                    }
                ),
                ( 'Congratulations shown first, not scrolled to footer ' . $suffix )
            );
            main::check( $b->{'button'}, ( 'Back to room action visible ' . $suffix ) );
            $p->screenshot(
                {
                    path =>
                      format_value( $out->child( ( $mode . '-' . $size->[0] . 'x' . $size->[1] . '.png' ) ) )
                }
            );
            if ( truth_value( ( ( $size->[0] < 641 ) ) ) ) {
                main::check(
                    (
                        value_eq(
                            evaluate_js(
                                $p->locator('#victoryStats tbody tr')->first(),
                                '(e)=>getComputedStyle(e).display'
                            ),
                            'grid'
                        )
                    ),
                    ( 'Mobile result cards ' . $suffix )
                );
                evaluate_js( $p->locator('#victoryDialog'), '(e)=>e.scrollTop=e.scrollHeight' );
                $p->screenshot(
                    {
                        path => format_value(
                            $out->child( ( $mode . '-lower-' . $size->[0] . 'x' . $size->[1] . '.png' ) )
                        )
                    }
                );
                main::check( $p->locator('#victoryCloseBtn')->isVisible(),
                    ( 'Dismissal remains reachable while scrolling ' . $suffix ) );
            }
            $saved = json_text($report);
            evaluate_js( $p,
                '__test.localRoom.players[0].name="LATER NAME";__test.hurt(__test.tanks[7],{owner:0});' );
            main::check( ( value_eq( json_text( main::state($p)->{'matchStats'} ), $saved ) ),
                ( 'Report frozen after end ' . $suffix ) );
            $p->locator('#victoryCloseBtn')->click();
            main::check(
                ( !truth_value( $p->locator('#victoryDialog')->isVisible() ) ),
                ( 'Dismisses without starting another match ' . $suffix )
            );
            $p->locator('#startRoomBtn')->click();
            main::check(
                (
                    do {
                        my $boolean_value =
                          ( !defined( main::state($p)->{'matchStats'} ) );
                        truth_value($boolean_value)
                          ? evaluate_js( $p,
'__test.matchStats.rows.every(p=>p.eliminations===0&&p.deaths===0&&p.hillSeconds===0)'
                          )
                          : $boolean_value;
                    }
                ),
                ( 'New match clears all totals ' . $suffix )
            );
            $p->context()->close();
            remove_item( $contexts, $p->context() );
        }
    }
    $p = main::load();
    main::setup( $p, 'elimination', 4 );
    main::start($p);
    $v = evaluate_js( $p,
'()=>{const T=__test;T.setPhase(\'playing\');T.hurt(T.tanks[2],{owner:0});const row=T.tanks[0].statsRow;T.startRound();T.setPhase(\'playing\');for(const t of T.tanks){t.invulnerable=0;t.human=true;}T.hurt(T.tanks[2],{owner:0});const kept=T.tanks[0].statsRow===row;const member=T.localRoom.players.find(p=>p.id===0);T.setPlayerSpectating(member,true);const deaths=row.deaths;T.setPlayerSpectating(member,false);const restored=T.tanks.find(t=>t.id===member.id).statsRow===row;T.setPhase(\'playing\');T.finishMatch(1);return{kept,restored,deaths,report:T.matchReport};}'
    );
    main::check(
        (
            do {
                my $boolean_value = $v->{'kept'};
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = $v->{'restored'};
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( value_eq( $v->{'deaths'}, 0 ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $v->{'report'}->{'players'}->[0]->{'eliminations'}, 2 ) )
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Local totals survive rounds and spectator toggles, not counted as deaths'
    );
    main::setup( $p, 'ctf', 4, JSON::PP::true );
    main::start($p);
    $v = evaluate_js( $p,
        '()=>{const T=__test;T.hurt(T.tanks[1],{owner:0});T.finishMatch(0);return T.matchReport;}' );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( $v->{'players'}->[0]->{'teamKills'}, 1 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( $v->{'players'}->[0]->{'eliminations'}, 0 ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $p->locator('[data-metric=teamKills]')->count(), 4 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Friendly-fire kills have their own column'
    );
    evaluate_js( $p,
'()=>{const r=JSON.parse(JSON.stringify(__test.matchReport));r.players[0].name=\'<img src=x onerror=alert(1)>\';r.players[0].mixedTeams=true;r.players[1].active=false;__test.renderMatchStats(r);}'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( $p->locator('#victoryStats img')->count(), 0 ) );
                truth_value($boolean_value)
                  ? ( contains_value( $p->locator('.stat-pilot-name')->first()->innerText(), '<img' ) )
                  : $boolean_value;
            }
        ),
        'Statistics render names as plain text'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( contains_value( $p->locator('#victoryStats')->innerText(), 'CHANGED TEAMS' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $p->locator('#victoryStats')->innerText(), 'PLAYED EARLIER' ) )
                  : $boolean_value;
            }
        ),
        'Changed-team and earlier-participant notes visible'
    );
    $host = main::load();
    main::setup( $host, 'ctf', 4 );
    $code = ( 'stats-' . unpack( "H*", random_bytes(4) ) );
    $host->locator('#localRoomName')->fill($code);
    evaluate_js( $host, '__test.shareLocalRoom()' );
    wait_js( $host, 'leqra.getState().online?.connected' );
    $guest = main::load( 'GUEST', undef, $code, undef );
    wait_js( $guest, 'leqra.getState().online?.connected' );
    $viewer = main::load( 'VIEWER', [ 320, 568 ], $code, JSON::PP::true );
    main::check( ( !truth_value( ( main::state($viewer)->{'online'} // undef ) ) ),
        'Watch link still waits for callsign confirmation' );
    $viewer->locator('#pilotName')->fill('VIEWER');
    $viewer->locator('#joinRoomBtn')->click();
    wait_js( $viewer, 'leqra.getState().online?.connected' );
    $guest->locator('#readyBtn')->click();
    wait_js( $host, '!document.querySelector("#startRoomBtn").disabled' );
    $host->locator('#startRoomBtn')->click();
    wait_js( $host, 'leqra.getState().phase==="playing"' );
    main::check(
        evaluate_js(
            $host,
            '__messages.filter(m=>m.type==="state"&&m.phase==="playing").every(s=>!("matchStats" in s))'
        ),
        'Live network snapshots exclude the results ledger'
    );
    main::fixture( $code, 'enemyKill37',  2 );
    main::fixture( $code, 'flagReturn37', 1 );
    main::fixture( $code, 'captureWin37', 0 );

    for $page ( @{ [ $host, $guest, $viewer ] } ) {
        wait_js( $page, 'document.querySelector("#victoryDialog").open' );
    }
    $expected = main::state($host)->{'matchStats'};
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( $expected->{'players'}->[0]->{'eliminations'}, 1 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( value_eq( $expected->{'players'}->[0]->{'captures'}, 1 ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $expected->{'players'}->[1]->{'flagReturns'}, 1 ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Go report carries actual enemy death, winning capture and local-P2 return'
    );
    main::check(
        !scalar(
            grep {
                my $pg = $_;
                !( ( value_eq( main::state($pg)->{'matchStats'}, $expected ) ) )
            } @{ [ $guest, $viewer ] }
        ),
        'Players and spectators receive identical authoritative results'
    );
    main::check(
        (
            do {
                my $boolean_value =
                  ( value_eq( scalar( @{ $expected->{'players'} } ), 5 ) );
                truth_value($boolean_value)
                  ? !scalar(
                    grep {
                        my $x = $_;
                        !( ( !value_eq( $x->{'name'}, 'VIEWER' ) ) )
                    } @{ $expected->{'players'} }
                  )
                  : $boolean_value;
            }
        ),
        'Watching alone does not invent a combat row'
    );
    $viewer->screenshot( { path => format_value( $out->child('online-spectator-320.png') ) } );
    $host->screenshot( { path => format_value( $out->child('online-report-desktop.png') ) } );
    $before = evaluate_js( $host, '__messages.filter(m=>m.type==="state"&&m.matchStats).at(-1).matchStats' );
    $host->locator('#victoryCloseBtn')->click();
    $Leqra::Browser::HANDLE->await( $host->waitForTimeout(200) );
    main::check(
        (
            do {
                my $boolean_value = ( !truth_value( $host->locator('#victoryDialog')->isVisible() ) );
                truth_value($boolean_value)
                  ? ( value_eq( main::state($host)->{'matchStats'}, $before ) )
                  : $boolean_value;
            }
        ),
        'Repeated end snapshots neither reopen popup nor change results'
    );
    $late = main::load( 'LATE VIEWER', [ 390, 844 ], $code, JSON::PP::true );
    $late->locator('#pilotName')->fill('LATE VIEWER');
    $late->locator('#joinRoomBtn')->click();
    wait_js( $late, 'document.querySelector("#victoryDialog").open' );
    main::check(
        ( value_eq( main::state($late)->{'matchStats'}, $expected ) ),
        'Late spectator receives the frozen completed-match report'
    );
    $sockets = evaluate_js( $guest, '__sockets.length' );
    evaluate_js( $guest, '__sockets.at(-1).close()' );
    wait_js( $guest, '(n)=>__sockets.length>n&&leqra.getState().online?.connected',
        $sockets, { timeout => 10000 } );
    wait_js( $guest, '__messages.filter(m=>m.type==="welcome").at(-1)?.resumed===true' );
    $Leqra::Browser::HANDLE->await( $guest->waitForTimeout(100) );
    main::check( ( value_eq( main::state($guest)->{'matchStats'}, $expected ) ),
        'Reconnect retains the completed report' );
    main::check( ( !truth_value($errors) ), 'No JavaScript page errors' );
    $report = {
        'version' => '3.7.1',
        'passed'  => scalar( @{$checks} ),
        'checks'  => $checks,
        'errors'  => $errors,
        'limits'  =>
'Chromium emulation, exact assets injected with Location/History/storage adapters, local Go fixture; not physical phones or public hosting.'
    };
    $out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
    print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
    1;
};
if ($@) {
    for my $item ( @{ [ map { [ $_, $pages->[$_] ] } 0 .. $#{$pages} ] } ) {
        my $tuple_103_6 = $item;
        my $i           = $tuple_103_6->[0];
        my $page        = $tuple_103_6->[1];
        if ( truth_value( ( !truth_value( $page->isClosed() ) ) ) ) {
            eval {
                $page->screenshot(
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
    $out->child('failure.json')->spew_utf8( json_text( { 'checks' => $checks, 'errors' => $errors }, 1 ) );
    die undef;
}
for $c ( @{$contexts} ) {
    eval {
        $c->close();
        1;
    };
    if ($@) {
    }
}
$browser->close();
