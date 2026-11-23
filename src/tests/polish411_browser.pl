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
    $a,      $ap,     $assets,  $b,      $badge, $bands, $c,    $centers,
    $checks, $errors, $f,       $groups, $h,     $html,  $i,    $icon,
    $js,     $key,    $metrics, $opts,   $out,   $p,     $prev, $pw,
    $r,      $tx,     $ty,      $w,      $web,   $x,     $y
);

# v4.11 focused browser checks: simpler Shotgun icon, loadout strip, local pause, FFA presets, remote/bot power badges.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'test-output/polish411' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish411_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish411_browser.pl --output
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
$checks = [];
$errors = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$c = $b->newContext( { viewport => { 'width' => 390, 'height' => 844 }, colorScheme => 'dark' } );
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
$p->setContent($html);
evaluate_js( $p,
'()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={\'leqra.name\':\'ALPHA\',\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}'
);

for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
    $p->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
}
$p->addScriptTag( { content => $js } );
wait_js( $p, 'window.__test&&leqra.version===\'4.11.0\'' );
$p->locator('#roomPresetsBtn')->click();
$opts = $p->locator('#presetSelect option')->allTextContents();
main::check( ( contains_value( $opts, '4-tank Free-for-all' ) ), '4-tank Free-for-all preset is available' );
main::check( ( contains_value( $opts, '8-tank Free-for-all' ) ), '8-tank Free-for-all preset is available' );
$p->locator('#presetSelect')->selectOption( { label => '8-tank Free-for-all' } );
$p->locator('#loadPresetBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    evaluate_js(
        $p,
'__test.localRoom.players.length===8&&__test.currentRules().teamMode===\'ffa\'&&__test.currentRules().mapSize===\'huge\''
    ),
    '8-tank FFA preset loads eight tanks on Huge 14×12'
);
$p->locator('#roomPresetsBtn')->click();
$p->locator('#presetSelect')->selectOption( { label => '4-tank Free-for-all' } );
$p->locator('#loadPresetBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    evaluate_js(
        $p,
'__test.localRoom.players.length===4&&__test.currentRules().teamMode===\'ffa\'&&__test.currentRules().mapSize===\'large\''
    ),
    '4-tank FFA preset loads four tanks on Large 12×10'
);
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
evaluate_js( $p, '__test.updateHUD(true)' );
$key = $p->locator('#loadoutKey1');
main::check( ( value_eq( $key->innerText(), 'Q / SPACE' ) ), 'single-player fire hint shows Q / SPACE' );
$metrics = evaluate_js( $key,
'e=>({client:e.clientWidth,scroll:e.scrollWidth,right:e.getBoundingClientRect().right,parent:e.parentElement.getBoundingClientRect().right})'
);
main::check(
    (
        do {
            my $boolean_value =
              ( ( $metrics->{'scroll'} <= ( $metrics->{'client'} + 1 ) ) );
            truth_value($boolean_value)
              ? ( ( $metrics->{'right'} <= ( $metrics->{'parent'} + 1 ) ) )
              : $boolean_value;
        }
    ),
    'Q / SPACE fire hint is not clipped'
);
main::check(
    ( value_eq( $p->locator('#bestInline')->innerText(), '' ) ),
    'offline FIRST TO 5 label removed from underbar'
);
evaluate_js( $p, '__test.setPhase(\'playing\')' );
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check( $p->locator('#restartLocalBtn')->isVisible(), 'local pause menu keeps Restart match' );
main::check( ( !truth_value( $p->locator('#onlineLeaveBtn')->isVisible() ) ),
    'local pause menu removes New local room button' );
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$icon = evaluate_js( $p,
'()=>{const cv=document.createElement(\'canvas\');cv.width=cv.height=52;const c=cv.getContext(\'2d\');c.translate(26,26);__test.powerIcon(\'scatter\',c);const d=c.getImageData(0,0,52,52).data;let ys=new Set(),right=0,left=0;for(let y=0;y<52;y++)for(let x=0;x<52;x++)if(d[(y*52+x)*4+3]){if(x>=35){ys.add(y);right++}if(x<=19)left++;}return{right,left,bands:[...ys]};}'
);
$bands  = $icon->{'bands'};
$groups = 0;
$prev   = undef;

for $y ( @{$bands} ) {
    if (
        truth_value(
            (
                do {
                    my $boolean_value = ( !defined($prev) );
                    truth_value($boolean_value)
                      ? $boolean_value
                      : ( ( $y > ( $prev + 1 ) ) );
                }
            )
        )
      )
    {
        $groups += 1;
    }
    $prev = $y;
}
main::check(
    (
        do {
            my $boolean_value = ( ( $groups >= 3 ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( ( $icon->{'right'} > 0 ) );
                truth_value($boolean_value)
                  ? ( ( $icon->{'left'} > 0 ) )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'Shotgun icon reads as one line branching into three shots'
);
$badge = evaluate_js( $p,
'()=>{const t=__test.tanks.find(t=>!t.human);Object.assign(t,{alive:true,power:\'scatter\',powerTime:10,shield:10,shieldCharges:2,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10});const kinds=__test.activeTankPowerBadges(t);const c=document.getElementById(\'arena\').getContext(\'2d\'),old=c.drawImage,calls=[];c.drawImage=function(...a){if(a.length>=5)calls.push([a[1],a[2],a[3],a[4]]);return old.apply(this,a)};try{__test.drawTankPowerBadges(t);}finally{c.drawImage=old}return{kinds,calls,x:t.x,y:t.y};}'
);
main::check( ( value_eq( $badge->{'kinds'}, [ 'scatter', 'shield', 'speed', 'scope', 'ghost' ] ) ),
    'bot badge list includes weapon and every active buff' );
main::check( ( value_eq( scalar( @{ $badge->{'calls'} } ), 5 ) ),
    'five active power-ups draw five cached badges' );
$centers = [
    map {
        my ( $x, $y, $w, $h ) = @{$_};
        [ ( $x + ( $w / 2 ) ), ( $y + ( $h / 2 ) ) ]
    } @{ $badge->{'calls'} }
];
my $tuple_49_1 = [ $badge->{'x'}, $badge->{'y'} ];
$tx = $tuple_49_1->[0];
$ty = $tuple_49_1->[1];
main::check(
    (
        do {
            my $boolean_value = ( ( $centers->[0]->[0] > $tx ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( ( $centers->[0]->[1] < $ty ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( ( $centers->[1]->[0] > $tx ) );
                    truth_value($boolean_value)
                      ? do {
                        my $boolean_value = ( ( $centers->[1]->[1] > $ty ) );
                        truth_value($boolean_value)
                          ? do {
                            my $boolean_value =
                              ( ( $centers->[2]->[0] < $tx ) );
                            truth_value($boolean_value)
                              ? do {
                                my $boolean_value =
                                  ( ( $centers->[2]->[1] > $ty ) );
                                truth_value($boolean_value)
                                  ? do {
                                    my $boolean_value =
                                      ( ( $centers->[3]->[0] < $tx ) );
                                    truth_value($boolean_value)
                                      ? ( ( $centers->[3]->[1] < $ty ) )
                                      : $boolean_value;
                                  }
                                  : $boolean_value;
                              }
                              : $boolean_value;
                          }
                          : $boolean_value;
                      }
                      : $boolean_value;
                  }
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'first four power badges progress clockwise from top-right'
);
$p->screenshot( { path => format_value( $out->child('playing-390x844.png') ) } );
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'    => '4.11.0',
            'passed'     => scalar( @{$checks} ),
            'checks'     => $checks,
            'errors'     => $errors,
            'shotgun'    => $icon,
            'keyMetrics' => $metrics,
            'badgeKinds' => $badge->{'kinds'}
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
