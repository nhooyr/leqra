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

my ( $a, $ap, $assets, $b, $c, $checks, $colors, $errors, $f, $feedback, $focus, $html, $i, $info, $js,
    $maze_before_resize, $out, $p, $pw, $r, $regen, $spectator, $stable, $tiers, $web, $x );

# v4.15 focused browser checks: stable lobby maze, ultra-wide tier, fixed-height per-pilot feedback, spectator wording.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'tests/results/v4.15-browser' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl polish415_browser.pl --output
';
    if ($help) {
        print 'Usage: perl polish415_browser.pl --output
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
$c = $b->newContext( { viewport => { 'width' => 1365, 'height' => 950 }, colorScheme => 'dark' } );
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
wait_js( $p, 'window.__test&&leqra.version===\'4.35.0\'' );
evaluate_js( $p, '__test.createLocalRoom()' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$tiers = evaluate_js( $p,
'()=>({giant:{dim:__test.mapDimensions(\'giant\'),cap:__test.pickupCap(16,14),start:__test.startingPickups(16,14),life:__test.pickupLifetime(16,14)},ultra:{dim:__test.mapDimensions(\'ultrawide\'),cap:__test.pickupCap(24,14),start:__test.startingPickups(24,14),life:__test.pickupLifetime(24,14)}})'
);
main::check(
    ( value_eq( $tiers->{'giant'}, { 'dim' => [ 16, 14 ], 'cap' => 23, 'start' => 6, 'life' => 61 } ) ),
    'Giant keeps 23 max pickups and the requested 61-second expiry' );
main::check(
    ( value_eq( $tiers->{'ultra'}, { 'dim' => [ 24, 14 ], 'cap' => 34, 'start' => 7, 'life' => 90 } ) ),
    'Ultra Wide is 24×14 with 7 starting, 34 max and 90-second pickup expiry' );
$stable = evaluate_js( $p,
'()=>{const before=JSON.stringify(__test.walls);const bot=__test.localRoom.players.find(x=>x.kind===\'bot\');__test.changeSeat(bot,{difficulty:\'hard\',name:\'RUSTY\'});const afterEdit=JSON.stringify(__test.walls);__test.addRoomSeat(\'local\');const afterAdd=JSON.stringify(__test.walls);return{sameEdit:before===afterEdit,sameAdd:before===afterAdd,players:__test.localRoom.players.length};}'
);
main::check(
    (
        do {
            my $boolean_value = $stable->{'sameEdit'};
            truth_value($boolean_value)
              ? do {
                my $boolean_value = $stable->{'sameAdd'};
                truth_value($boolean_value)
                  ? ( value_eq( $stable->{'players'}, 5 ) )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'renaming/tuning roster and adding local P2 do not regenerate the lobby maze'
);
$regen = evaluate_js( $p,
'()=>{const base=JSON.stringify(__test.walls),r=__test.currentRules();__test.setLocalRules({...r,teamMode:\'teams\'});const afterTeam=JSON.stringify(__test.walls);const teamSelects=document.querySelectorAll(\'#roomRoster select[data-team]\').length;__test.setLocalRules({...__test.currentRules(),teamMode:\'ffa\'});const ffaWall=JSON.stringify(__test.walls),ffaSelects=document.querySelectorAll(\'#roomRoster select[data-team]\').length;__test.setLocalRules({...__test.currentRules(),mapSize:\'ultrawide\'});return{sameTeam:base===afterTeam,sameFFA:base===ffaWall,teamSelects,ffaSelects,cols:leqra.getState().world.cols,rows:leqra.getState().world.rows,changed:base!==JSON.stringify(__test.walls)};}'
);
main::check(
    (
        do {
            my $boolean_value = $regen->{'sameTeam'};
            truth_value($boolean_value) ? $regen->{'sameFFA'} : $boolean_value;
        }
    ),
    'team/FFA rule edits preserve the lobby maze'
);
main::check(
    (
        do {
            my $boolean_value = ( ( $regen->{'teamSelects'} > 0 ) );
            truth_value($boolean_value)
              ? ( value_eq( $regen->{'ffaSelects'}, 0 ) )
              : $boolean_value;
        }
    ),
    'FFA removes tank team selectors instead of showing locked controls'
);
main::check(
    (
        do {
            my $boolean_value = ( value_eq( $regen->{'cols'}, 24 ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( value_eq( $regen->{'rows'}, 14 ) );
                truth_value($boolean_value)
                  ? $regen->{'changed'}
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'changing maze size regenerates into the 24×14 Ultra Wide layout'
);
$maze_before_resize = evaluate_js( $p, 'JSON.stringify(__test.walls)' );
$p->setViewportSize( { 'width' => 700, 'height' => 950 } );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(120) );
$p->setViewportSize( { 'width' => 1365, 'height' => 950 } );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(120) );
main::check(
    ( value_eq( evaluate_js( $p, 'JSON.stringify(__test.walls)' ), $maze_before_resize ) ),
    'responsive layout changes resize the same lobby maze instead of regenerating it'
);
$info = evaluate_js( $p,
'()=>{__test.syncControlsPickupInfo();return document.querySelector(\'#controlsPickupInfo\').textContent;}'
);
main::check(
    (
        do {
            my $boolean_value = ( contains_value( $info, '7 starting power-ups' ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( contains_value( $info, '34 maximum' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $info, '90 seconds' ) )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'Controls menu shows starting/max power-ups and maze-dependent expiry'
);
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(30) );
evaluate_js( $p, '()=>{__test.setPhase(\'playing\');__test.updateHUD(true)}' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$feedback = evaluate_js( $p,
'()=>{const box=document.querySelector(\'#localLoadouts\'),before=box.getBoundingClientRect().height;__test.showStartingControls();__test.updateHUD(true);const p1=document.querySelector(\'#buffLabel\').textContent,p2=document.querySelector(\'#buffLabel2\').textContent,afterControls=box.getBoundingClientRect().height;const t2=__test.tanks.find(t=>t.id===__test.localRoom.players.find(p=>p.kind===\'local\').id);__test.pickups.push({x:t2.x,y:t2.y,type:\'laser\',age:0,life:45});__test.update(1/60);__test.updateHUD(true);return{before,afterControls,afterPickup:box.getBoundingClientRect().height,p1,p2,p2Pickup:document.querySelector(\'#buffLabel2\').textContent,p2Visible:!document.querySelector(\'#pilotLoadout2\').hidden};}'
);
main::check(
    (
        do {
            my $boolean_value = $feedback->{'p2Visible'};
            truth_value($boolean_value)
              ? do {
                my $boolean_value =
                  ( index( $feedback->{'p1'}, 'CONTROLS' ) == 0 );
                truth_value($boolean_value)
                  ? ( index( $feedback->{'p2'}, 'CONTROLS' ) == 0 )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'P1 and local P2 each receive their own controls feedback beside ammo'
);
main::check(
    (
        do {
            my $boolean_value = ( ( abs( ( $feedback->{'before'} - $feedback->{'afterControls'} ) ) < 0.6 ) );
            truth_value($boolean_value)
              ? ( ( abs( ( $feedback->{'before'} - $feedback->{'afterPickup'} ) ) < 0.6 ) )
              : $boolean_value;
        }
    ),
    'controls/pickup feedback does not change the player-status area height'
);
main::check( ( index( $feedback->{'p2Pickup'}, 'LASER' ) == 0 ),
    'a local P2 pickup replaces only P2’s reserved feedback line with pickup details' );
evaluate_js( $p, '__test.render()' );
$p->screenshot( { path => format_value( $out->child('v415-hud.png') ) } );
$focus = evaluate_js( $p,
    '()=>{__test.setPhase(\'playing\');window.dispatchEvent(new Event(\'blur\'));return __test.phase;}' );
main::check( ( value_eq( $focus, 'playing' ) ), 'window focus loss does not pause local gameplay' );
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check( ( value_eq( trim_text( $p->locator('#menuControlsBtn')->innerText(), 'strip' ), 'Controls' ) ),
    'pause-menu action is labeled Controls' );
$spectator = evaluate_js( $p,
'()=>{const body=document.body.innerText,matches=body.match(/NO TANK ASSIGNED|\\bWATCHING\\b|\\bWATCHERS?\\b/gi)||[];return{caption:document.querySelector(\'#watchingCaption\').textContent,matches,sourceNoLegacy:!matches.length};}'
);
main::check(
    (
        do {
            my $boolean_value =
              ( contains_value( $spectator->{'caption'}, 'SPECTATING' ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( !( contains_value( $spectator->{'caption'}, 'NO TANK ASSIGNED' ) ) );
                truth_value($boolean_value)
                  ? $spectator->{'sourceNoLegacy'}
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'spectator UI uses Spectators/Spectating and omits NO TANK ASSIGNED'
);
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
evaluate_js( $p, '()=>{__test.setPhase(\'matchOver\');__test.showVictory(__test.tanks[0].id)}' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$colors = inspect_elements( $p, '#victoryScores .match-result',
'rows=>rows.map(r=>({expected:r.style.getPropertyValue(\'--result-color\'),actual:getComputedStyle(r.querySelector(\'strong\')).color}))'
);
main::check(
    (
        do {
            my $boolean_value = ( ( scalar( @{$colors} ) >= 2 ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = !scalar( grep { my $x = $_; !( $x->{'expected'} ) } @{$colors} );
                truth_value($boolean_value)
                  ? (
                    ( scalar( @{ unique_values( [ map { my $x = $_; $x->{'actual'} } @{$colors} ] ) } ) > 1 )
                  )
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'victory score values use the tank/team result colors'
);
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$p->screenshot( { path => format_value( $out->child('v415-desktop.png') ) } );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'            => '4.35.0',
            'passed'             => scalar( @{$checks} ),
            'checks'             => $checks,
            'errors'             => $errors,
            'tiers'              => $tiers,
            'feedback'           => $feedback,
            'controlsPickupInfo' => $info
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
