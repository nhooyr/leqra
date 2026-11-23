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
    $a, $ap, $b, $c,      $checks, $errors, $h, $k, $old, $out,
    $p, $pw, $r, $report, $result, $src,    $u, $w, $x,   $z
);

# Deterministic browser regressions, exact shipped assets (optional v4.1 baseline).
# A fake monotonic clock and read-only snapshots isolate rendering from scheduling.
# This is not a WAN/frame-rate benchmark. No production code is instrumented on disk.
$ap = {};
$a  = do {
    my %args = (
        'assets'   => undef,
        'baseline' => undef,
        'output'   => 'test-output/feel42-repro'
    );
    my $help;
    GetOptions(
        'assets=s'   => \$args{'assets'},
        'baseline=s' => \$args{'baseline'},
        'output=s'   => \$args{'output'},
        'help|h'     => \$help
      )
      or die 'Usage: perl feel42_repro.pl --assets --baseline --output
';
    if ($help) {
        print 'Usage: perl feel42_repro.pl --assets --baseline --output
';
        exit 0;
    }
    \%args;
};
$r   = path($0)->absolute->parent(2);
$out = path( $a->{'output'} );
$out->mkpath;

sub assets {
    my ($path) = @_;
    my ( $directory, $name, $sources, $web );
    $web       = path($path);
    $directory = asset_directory($web);
    $sources =
      { map { my $name = $_; $name => ( $directory / $name )->slurp_utf8 }
          @{ [ 'game.js', 'netcode.js', 'style.css' ] } };
    $sources->{'index.html'} = $web->child('index.html')->slurp_utf8;
    return $sources;
}

sub load {
    my ( $b, $src, $w, $h ) = @_;
    my ( $c, $errors, $html, $i, $js, $p );
    $w //= 1365;
    $h //= 950;
    $c = $b->newContext(
        {
            viewport => { 'width' => $w, 'height' => $h },
            isMobile => (
                do {
                    my $boolean_value = ( ( $w < 760 ) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( ( $h < 620 ) );
                }
            ),
            hasTouch => (
                do {
                    my $boolean_value = ( ( $w < 760 ) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( ( $h < 620 ) );
                }
            )
        }
    );
    $p      = $c->newPage();
    $errors = [];
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $html = replace_re( '<link[^>]*>', '', $src->{'index.html'} );
    $html = replace_text( replace_re( '<script src="[^"]+" defer></script>', '', $html ),
        '</head>', ( ( '<style>' . $src->{'style.css'} ) . '</style></head>' ) );
    $p->setContent($html);
    evaluate_js(
        $p,
'()=>{window.__clock=1000;Object.defineProperty(performance,\'now\',{value:()=>window.__clock});window.requestAnimationFrame=()=>0;
 for(const name of [\'localStorage\',\'sessionStorage\']){const d={\'leqra.muted\':\'1\'};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}
 window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={replaceState(){}};}'
    );
    $js = replace_text( $src->{'game.js'}, '(() => {', '((location,history) => {', 1 );
    $i  = rindex( $js, '})()' );
    $js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location,window.__history);' )
        . substr( $js, ( $i + 4 ) ) );
    $js = replace_text(
        $js,
        'window.__test={',
'window.__test={ setupNetwork42:()=>{mode=\'online\';online.connected=true;online.id=0;online.code=\'TEST42\';online.seq=0;online.socket={readyState:1,bufferedAmount:0,send(){},close(){}};online.roomData={...localRoom,code:\'TEST42\',phase:\'playing\',host:0};resetOnlineMotion();online.generation=-1;},',
        1
    );
    $p->addScriptTag( { content => $src->{'netcode.js'} } );
    $p->addScriptTag( { content => $js } );
    wait_js( $p, 'window.__test' );
    evaluate_js(
        $p,
'()=>{window.net42=()=>{const T=__test;T.startRound();const world={cols:12,rows:10,width:1008,height:840,walls:[{x:-4,y:-4,w:1016,h:8,axis:\'h\'},{x:-4,y:836,w:1016,h:8,axis:\'h\'},{x:-4,y:-4,w:8,h:848,axis:\'v\'},{x:1004,y:-4,w:8,h:848,axis:\'v\'}]};
 const ts=T.tanks.map((t,i)=>({...t,bot:false,x:200+i*84,y:210,angle:0,alive:true,cooldown:0,cooldownTotal:.34,shotSerial:0,spawnSerial:1,ack:0,ackSteps:0}));T.setupNetwork42();
 window.snap42={tick:60,generation:1,phase:\'playing\',round:1,phaseTime:0,roundClock:70,winner:-1,scores:[0,0,0,0,0,0,0,0],tanks:ts,bullets:[],pickups:[],events:[],rules:T.currentRules(),objectives:null,world};
 T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);return T;};}'
    );
    return [ $p, $c, $errors ];
}

sub probe {
    my ( $b, $src ) = @_;
    my ( $c, $errors, $p, $result );
    my $tuple_35_1 = main::load( $b, $src );
    $p      = $tuple_35_1->[0];
    $c      = $tuple_35_1->[1];
    $errors = $tuple_35_1->[2];
    $result = {};
    eval {
        $result->{'buttonWriterConflict'} = evaluate_js( $p,
'()=>{const T=__test;T.startRound();T.setPhase(\'playing\');const t=T.tanks[0];t.cooldown=.32;t.cooldownTotal=.34;T.updateCombatFeedback(true);const a=document.querySelector(\'#fireLabel\').textContent;__clock+=1;T.updateHUD();const b=document.querySelector(\'#fireLabel\').textContent;return{before:a,after:b,conflict:a!==b};}'
        );
        $result->{'frozenRound'} = evaluate_js( $p,
'()=>{const T=net42(),labels=new Set(),values=new Set();snap42.phase=\'roundOver\';snap42.winner=0;snap42.tanks[0].cooldown=.21;for(let k=0;k<120;k++){__clock+=1000/120;if(k%4===0){snap42.tick+=2;T.receiveOnlineState(structuredClone(snap42));}T.renderOnlineMotion(1/120,__clock);T.updateCombatFeedback(true);labels.add(document.querySelector(\'#cooldownText1\').textContent);values.add(document.querySelector(\'#cooldownFill1\').style.transform);}return{labels:[...labels],distinctFillValues:values.size};}'
        );
        $result->{'remoteBirth'} = evaluate_js( $p,
'()=>{const T=net42();const bullet={id:101,owner:1,x:320,y:210,vx:282,vy:0,r:3.5,age:.05,life:5,color:\'#ff9679\',bounces:0,kind:\'\',shotSerial:1,spawnSerial:1,pellet:0};__clock+=66;snap42.tick=64;snap42.bullets=[bullet];T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);const early=T.bullets.find(b=>b.id===101)?.x??null;__clock+=66;snap42.tick=68;snap42.bullets[0].x=338.8;snap42.bullets[0].age+=.066666;T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);const future=T.bullets.find(b=>b.id===101)?.x??null;T.online.buffer.time=65*1000/60;T.renderOnlineMotion(0,__clock);const later=T.bullets.find(b=>b.id===101)?.x??null;return{early,future,later,backwards:future!==null&&later<future};}'
        );
        if ( truth_value( ( contains_value( $src->{'game.js'}, 'previewOnlineFire' ) ) ) ) {
            $result->{'laserWithFullAmmo'} = evaluate_js( $p,
'()=>{const T=net42();const t=snap42.tanks[0];t.power=\'laser\';t.charges=3;t.powerTime=10;snap42.tick+=2;snap42.bullets=Array.from({length:5},(_,i)=>({id:200+i,owner:0,x:320+i*30,y:630,vx:282,vy:0,r:3.5,age:.7,life:4,color:t.color,bounces:0,kind:\'\',shotSerial:0,spawnSerial:1,pellet:0}));__clock+=34;T.receiveOnlineState(structuredClone(snap42));T.renderOnlineMotion(0,__clock);T.previewOnlineFire(false,{fire:true},__clock);const n=T.online.shots.previews.size;const trace=T.traces.at(-1),before=trace?.life;__clock+=100;T.onlineEffect({type:\'laser\',player:0,spawnSerial:1,shotSerial:1,x:200,y:210,endX:284,endY:210,color:t.color,points:[{x:200,y:210},{x:284,y:210}]},T.online.snapshots.at(-1));return{previews:n,traces:T.traces.length,lifeUnchanged:T.traces.at(-1)?.life===before,authoritativeBullets:T.online.snapshots.at(-1).bullets.length};}'
            );
        }
        $result->{'errors'} = $errors;
        1;
    };
    my $caught_error = $@;
    $c->close();
    die $caught_error if $caught_error;
    return $result;
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$report = {};
eval {
    if ( truth_value( $a->{'baseline'} ) ) {
        $z   = open_archive( $a->{'baseline'} );
        $old = {
            map {
                my $k = $_;
                $k => Encode::decode_utf8( $z->contents( ( 'leqra-online/web/' . $k ) ) )
            } @{ [ 'game.js', 'netcode.js', 'index.html', 'style.css' ] }
        };
        $report->{'baseline'} = main::probe( $b, $old );
    }
    $src = main::assets(
        (
            do {
                my $boolean_value = $a->{'assets'};
                truth_value($boolean_value) ? $boolean_value : $r->child('web');
            }
        )
    );
    $report->{'updated'} = main::probe( $b, $src );
    $u = $report->{'updated'};
    assert_ok( ( !truth_value( $u->{'buttonWriterConflict'}->{'conflict'} ) ), $u );
    assert_ok(
        (
            do {
                my $boolean_value = ( value_eq( $u->{'frozenRound'}->{'labels'}, ['ROUND COMPLETE'] ) );
                truth_value($boolean_value)
                  ? ( value_eq( $u->{'frozenRound'}->{'distinctFillValues'}, 1 ) )
                  : $boolean_value;
            }
        ),
        $u
    );
    assert_ok(
        (
            do {
                my $boolean_value =
                  ( defined( $u->{'remoteBirth'}->{'later'} ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( !truth_value( $u->{'remoteBirth'}->{'backwards'} ) );
                    truth_value($boolean_value)
                      ? ( !truth_value( $u->{'errors'} ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        $u
    );
    assert_ok(
        (
            value_eq(
                $u->{'laserWithFullAmmo'},
                {
                    'previews'             => 1,
                    'traces'               => 1,
                    'lifeUnchanged'        => JSON::PP::true,
                    'authoritativeBullets' => 5
                }
            )
        ),
        $u
    );
    $checks = [];
    for my $item ( @{ [ [ 1365, 950 ], [ 390, 844 ], [ 320, 568 ], [ 844, 390 ] ] } ) {
        my $tuple_57_6 = $item;
        my $w          = $tuple_57_6->[0];
        my $h          = $tuple_57_6->[1];
        my $tuple_58_3 = main::load( $b, $src, $w, $h );
        my $p          = $tuple_58_3->[0];
        my $c          = $tuple_58_3->[1];
        my $errors     = $tuple_58_3->[2];
        eval {
            $p->locator('#addLocalBtn')->click();
            $p->locator('#startRoomBtn')->click();
            my $result = evaluate_js( $p,
'()=>{const T=__test;T.setPhase(\'playing\');const before=document.querySelector(\'#arenaWrap\').getBoundingClientRect().toJSON();const outputs=[];for(const phase of [\'playing\',\'roundOver\',\'matchOver\',\'paused\',\'countdown\']){T.setPhase(phase);for(const t of T.tanks){t.cooldown=.19;t.cooldownTotal=.34;}T.updateHUD(true);T.updateCombatFeedback(true);outputs.push([phase,document.querySelector(\'#cooldownText1\').textContent,document.querySelector(\'#cooldownText2\').textContent]);}const after=document.querySelector(\'#arenaWrap\').getBoundingClientRect().toJSON();T.setPhase(\'roundOver\');T.updateHUD(true);T.render();return{outputs,before,after,overflow:document.body.scrollWidth>innerWidth+1};}'
            );
            assert_ok(
                (
                    do {
                        my $boolean_value =
                          ( !truth_value( $result->{'overflow'} ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $result->{'before'}->{'height'}, $result->{'after'}->{'height'} ) )
                          : $boolean_value;
                    }
                ),
                $result
            );
            assert_ok(
                !scalar(
                    grep { my $x = $_; !( ( value_eq( $x->[1], $x->[2] ) ) ) } @{ $result->{'outputs'} }
                ),
                $result
            );
            assert_ok(
                (
                    do {
                        my $boolean_value = ( value_eq( $result->{'outputs'}->[1]->[1], 'ROUND COMPLETE' ) );
                        truth_value($boolean_value)
                          ? ( value_eq( $result->{'outputs'}->[2]->[1], 'MATCH COMPLETE' ) )
                          : $boolean_value;
                    }
                ),
                $result
            );
            $p->screenshot(
                {
                    path => format_value( $out->child( ( 'result-' . $w . 'x' . $h . '.png' ) ) )
                }
            );
            push( @{$checks}, { 'viewport' => [ $w, $h ], %{$result} } );
            assert_ok( ( !truth_value($errors) ), $errors );
            1;
        };
        my $caught_error = $@;
        $c->close();
        die $caught_error if $caught_error;
    }
    $report->{'layoutChecks'} = $checks;
    $report->{'passed'}       = JSON::PP::true;
    1;
};
my $caught_error = $@;
$b->close();
$out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", json_text( $report, 1 ) ), "\n" );
die $caught_error if $caught_error;
