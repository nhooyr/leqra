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
    $after,   $args,    $assets, $before,              $blur,       $bounds,
    $browser, $c,       $checks, $dims,                $errors,     $fire,
    $font,    $gesture, $html,   $i,                   $js,         $out,
    $p,       $parser,  $plat,   $pw,                  $ratio,      $reads,
    $report,  $reset,   $root,   $safari_ipad_desktop, $safari_mac, $safari_phone,
    $st,      $web
);

# v4.19 Safari/WebKit compatibility regression checks.
#
# Chromium is used as a DOM/JS host with Safari/iOS identities because this build
# container cannot install Playwright WebKit. These checks validate the shipped
# Safari code/CSS paths, touch classification and release fallbacks; physical
# Safari is still listed separately in the release limits.
$root   = path($0)->absolute->parent(2);
$web    = $root->child('web');
$assets = asset_directory($web);
$parser = {};
$args   = do {
    my %args = ( 'output' => format_value( $root->child('tests/results/v4.19-safari') ) );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl safari419_browser.pl --output
';
    if ($help) {
        print 'Usage: perl safari419_browser.pl --output
';
        exit 0;
    }
    \%args;
};
$out = path( $args->{'output'} );
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

sub install {
    my ( $page, $platform, $max_touch ) = @_;
    my ($f);
    $page->setContent($html);
    evaluate_js(
        $page,
'a=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const store={getItem(){return null},setItem(){},removeItem(){}};Object.defineProperty(window,\'localStorage\',{value:store});Object.defineProperty(window,\'sessionStorage\',{value:store});window.__nativeAudioPlays=0;window.Audio=class{constructor(){this.src=\'\';this.volume=1;this.currentTime=0;this.preload=\'\';this.playsInline=false;this.dataset={};}setAttribute(){}pause(){}load(){}play(){window.__nativeAudioPlays++;return Promise.resolve();}};window.AudioContext=undefined;window.webkitAudioContext=undefined;try{Object.defineProperty(navigator,\'platform\',{value:a.platform,configurable:true});Object.defineProperty(navigator,\'maxTouchPoints\',{value:a.maxTouch,configurable:true});Object.defineProperty(navigator,\'userAgentData\',{value:undefined,configurable:true});}catch(_){}}',
        { 'platform' => $platform, 'maxTouch' => $max_touch }
    );
    for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
        $page->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
    }
    $page->addScriptTag( { content => $js } );
    wait_js( $page, 'window.__test&&leqra.version===\'4.35.0\'' );
}
$safari_mac =
'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
$safari_phone =
'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1';
$safari_ipad_desktop =
'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/605.1.15';
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$c = $browser->newContext(
    {
        viewport          => { 'width' => 1365, 'height' => 950 },
        deviceScaleFactor => 2,
        userAgent         => $safari_mac,
        colorScheme       => 'dark'
    }
);
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => ("desktop: " + String(e))' );
main::install( $p, 'MacIntel', 0 );
$plat = evaluate_js( $p, '__test.platform' );
main::check(
    (
        value_eq(
            $plat,
            {
                'webkit' => JSON::PP::true,
                'safari' => JSON::PP::true,
                'ios'    => JSON::PP::false
            }
        )
    ),
    'desktop Safari selects the WebKit/Safari optimization path'
);
main::check(
    evaluate_js(
        $p->locator('body'),
        'e=>e.classList.contains(\'webkit-engine\')&&e.classList.contains(\'safari-browser\')'
    ),
    'desktop Safari receives WebKit CSS performance class'
);
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $p->locator('#browserNotice')->count(), 1 ) );
            truth_value($boolean_value)
              ? ( contains_value( $p->locator('#browserNotice')->innerText(), 'Chrome or Firefox' ) )
              : $boolean_value;
        }
    ),
    'desktop Safari recommends Chrome or Firefox'
);
$before = evaluate_js( $p, '__nativeAudioPlays' );
$p->locator('#soundBtn')->dispatchEvent('pointerdown');
evaluate_js( $p, '__test.chatNotificationSound()' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
$after = evaluate_js( $p, '__nativeAudioPlays' );
main::check( ( ( $after > $before ) ),
    'desktop Safari sound uses the native-audio fallback even without a usable WebAudio context' );
$ratio = evaluate_js( $p, '__test.renderPixelRatio(1200,700)' );
main::check( ( ( 1 <= $ratio ) && ( $ratio <= 1.75 ) ),
    'desktop Safari caps adaptive Canvas pixel density at 1.75x' );
$blur = evaluate_js( $p,
'getComputedStyle(document.querySelector(\'.overlay\')).webkitBackdropFilter||getComputedStyle(document.querySelector(\'.overlay\')).backdropFilter'
);
main::check( ( contains_value( [ 'none', '' ], $blur ) ), 'Safari path disables full-arena backdrop blur' );
$dims = evaluate_js( $p,
'()=>{const w=document.querySelector(\'#arenaWrap\'),orig=w.getBoundingClientRect;let width=800,height=500;w.getBoundingClientRect=()=>({width,height,left:0,top:0,right:width,bottom:height,x:0,y:0});__test.resize();const a=[arena.width,arena.height];width=800.45;__test.resize();const b=[arena.width,arena.height];w.getBoundingClientRect=orig;return{a,b};}'
);
main::check( ( value_eq( $dims->{'a'}, $dims->{'b'} ) ),
    'fractional WebKit layout jitter does not reallocate Canvas for a 1px wobble' );
$p->screenshot( { path => format_value( $out->child('safari-desktop-path.png') ) } );
$c->close();
$c = $browser->newContext(
    {
        viewport          => { 'width' => 390, 'height' => 844 },
        deviceScaleFactor => 3,
        userAgent         => $safari_phone,
        isMobile          => JSON::PP::true,
        hasTouch          => JSON::PP::true,
        colorScheme       => 'dark'
    }
);
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => ("iphone: " + String(e))' );
main::install( $p, 'iPhone', 5 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(40) );
$plat = evaluate_js( $p, '__test.platform' );
main::check(
    (
        value_eq(
            $plat,
            {
                'webkit' => JSON::PP::true,
                'safari' => JSON::PP::true,
                'ios'    => JSON::PP::true
            }
        )
    ),
    'iPhone Safari selects iOS WebKit path'
);
main::check(
    ( value_eq( $p->locator('#browserNotice')->count(), 0 ) ),
    'iPhone Safari does not show the desktop browser recommendation'
);
$before = evaluate_js( $p, '__nativeAudioPlays' );
$p->locator('#soundBtn')->dispatchEvent('touchstart');
evaluate_js( $p, '__test.pickupSound ? __test.pickupSound() : __test.chatNotificationSound()' );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(20) );
main::check(
    ( ( evaluate_js( $p, '__nativeAudioPlays' ) > $before ) ),
    'iPhone Safari native-audio fallback survives touch-unlock flow'
);
$st = evaluate_js( $p, 'leqra.getState()' );
main::check( ( value_eq( $st->{'touchUI'}, JSON::PP::true ) ), 'iPhone Safari receives touch controls' );
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
$ratio = evaluate_js( $p, '__test.renderPixelRatio(390,650)' );
main::check( ( ( 1 <= $ratio ) && ( $ratio <= 1.5 ) ),
    'iPhone Safari caps Canvas density at 1.5x instead of native 3x' );
main::check( evaluate_js( $p, 'document.documentElement.scrollWidth<=innerWidth' ),
    'iPhone Safari path has no horizontal page overflow' );
$font = evaluate_js( $p, 'getComputedStyle(document.querySelector(\'#presetName\')).fontSize' );
main::check( ( ( ( 0 + remove_suffix( $font, 'px' ) ) >= 16 ) ),
    'iPhone Safari editable controls stay at 16px to prevent focus auto-zoom' );
main::check(
    (
        do {
            my $boolean_value =
              ( defined( $p->locator('canvas[data-power-icon]')->first()->getAttribute('width') ) );
            truth_value($boolean_value)
              ? ( ( int( $p->locator('canvas[data-power-icon]')->first()->getAttribute('width') ) <= 52 ) )
              : $boolean_value;
        }
    ),
    'Safari power-up legend caps icon backing resolution at 2x'
);
$reads = evaluate_js( $p,
'()=>{const base=stickBase,zone=stickZone,orig=base.getBoundingClientRect.bind(base);let reads=0;base.getBoundingClientRect=()=>{reads++;return orig()};const r=orig(),id=66;zone.dispatchEvent(new PointerEvent(\'pointerdown\',{pointerId:id,clientX:r.left+r.width*.55,clientY:r.top+r.height*.55,bubbles:true,cancelable:true,pointerType:\'touch\'}));for(let i=0;i<20;i++)zone.dispatchEvent(new PointerEvent(\'pointermove\',{pointerId:id,clientX:r.left+r.width*(.45+i*.01),clientY:r.top+r.height*.55,bubbles:true,cancelable:true,pointerType:\'touch\'}));window.dispatchEvent(new PointerEvent(\'pointerup\',{pointerId:id,bubbles:true,cancelable:true,pointerType:\'touch\'}));base.getBoundingClientRect=orig;return reads;}'
);
main::check( ( value_eq( $reads, 1 ) ),
    'Safari joystick caches geometry instead of forcing layout on every pointer move' );
$reset = evaluate_js( $p,
'()=>{const z=stickZone,b=z.getBoundingClientRect(),id=77;z.setPointerCapture=()=>{throw new Error(\'simulated WebKit capture loss\')};z.dispatchEvent(new PointerEvent(\'pointerdown\',{pointerId:id,clientX:b.left+b.width*.75,clientY:b.top+b.height*.3,bubbles:true,cancelable:true,pointerType:\'touch\'}));const moved=stickKnob.style.transform;window.dispatchEvent(new PointerEvent(\'pointerup\',{pointerId:id,bubbles:true,cancelable:true,pointerType:\'touch\'}));return{moved,after:stickKnob.style.transform};}'
);
main::check(
    (
        do {
            my $boolean_value =
              ( !( contains_value( [ 'translate(0,0)', 'translate(0px, 0px)' ], $reset->{'moved'} ) ) );
            truth_value($boolean_value)
              ? ( contains_value( [ 'translate(0,0)', 'translate(0px, 0px)' ], $reset->{'after'} ) )
              : $boolean_value;
        }
    ),
    'lost pointer capture cannot leave the Safari joystick stuck'
);
$fire = evaluate_js( $p,
'()=>{const id=88;fireBtn.setPointerCapture=()=>{throw new Error(\'simulated WebKit capture loss\')};fireBtn.dispatchEvent(new PointerEvent(\'pointerdown\',{pointerId:id,bubbles:true,cancelable:true,pointerType:\'touch\'}));const held=fireBtn.classList.contains(\'held\');window.dispatchEvent(new PointerEvent(\'pointercancel\',{pointerId:id,bubbles:true,cancelable:true,pointerType:\'touch\'}));return{held,after:fireBtn.classList.contains(\'held\')};}'
);
main::check(
    (
        do {
            my $boolean_value = $fire->{'held'};
            truth_value($boolean_value)
              ? ( !truth_value( $fire->{'after'} ) )
              : $boolean_value;
        }
    ),
    'lost/cancelled Safari fire pointer cannot leave FIRE held'
);
$gesture = evaluate_js( $p,
'()=>{const e=new Event(\'gesturestart\',{bubbles:true,cancelable:true});touchControls.dispatchEvent(e);return e.defaultPrevented;}'
);
main::check( $gesture, 'Safari multi-touch gesture zoom is suppressed over game controls' );
$p->screenshot( { path => format_value( $out->child('safari-iphone-path.png') ) } );
$c->close();
$c = $browser->newContext(
    {
        viewport          => { 'width' => 844, 'height' => 390 },
        deviceScaleFactor => 3,
        userAgent         => $safari_phone,
        isMobile          => JSON::PP::true,
        hasTouch          => JSON::PP::true,
        colorScheme       => 'dark'
    }
);
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => ("iphone-landscape: " + String(e))' );
main::install( $p, 'iPhone', 5 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(40) );
$st = evaluate_js( $p, 'leqra.getState()' );
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $st->{'touchUI'}, JSON::PP::true ) );
            truth_value($boolean_value)
              ? ( value_eq( $st->{'touchLandscape'}, JSON::PP::true ) )
              : $boolean_value;
        }
    ),
    'iPhone Safari landscape selects compact touch-landscape layout'
);
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(80) );
main::check(
    evaluate_js( $p, 'document.documentElement.scrollWidth<=innerWidth' ),
    'iPhone Safari landscape has no horizontal page overflow'
);
$bounds = evaluate_js( $p,
'()=>{const a=document.querySelector(\'.arena-shell\').getBoundingClientRect(),t=touchControls.getBoundingClientRect();return{arenaRight:a.right,arenaBottom:a.bottom,touchRight:t.right,touchBottom:t.bottom,w:innerWidth,h:innerHeight}}'
);
main::check(
    (
        do {
            my $boolean_value =
              ( ( $bounds->{'arenaRight'} <= ( $bounds->{'w'} + 1 ) ) );
            truth_value($boolean_value)
              ? ( ( $bounds->{'touchRight'} <= ( $bounds->{'w'} + 1 ) ) )
              : $boolean_value;
        }
    ),
    'iPhone Safari landscape arena and touch HUD stay within viewport width'
);
main::check(
    ( ( $bounds->{'touchBottom'} <= ( $bounds->{'h'} + 1 ) ) ),
    'iPhone Safari landscape touch HUD stays within viewport height'
);
$p->screenshot( { path => format_value( $out->child('safari-iphone-landscape-path.png') ) } );
$c->close();
$c = $browser->newContext(
    {
        viewport          => { 'width' => 1024, 'height' => 768 },
        deviceScaleFactor => 2,
        userAgent         => $safari_ipad_desktop,
        isMobile          => JSON::PP::false,
        hasTouch          => JSON::PP::false,
        colorScheme       => 'dark'
    }
);
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => ("ipad: " + String(e))' );
main::install( $p, 'MacIntel', 5 );
$Leqra::Browser::HANDLE->await( $p->waitForTimeout(40) );
$plat = evaluate_js( $p, '__test.platform' );
$st   = evaluate_js( $p, 'leqra.getState()' );
main::check(
    (
        do {
            my $boolean_value = $plat->{'ios'};
            truth_value($boolean_value) ? $plat->{'webkit'} : $boolean_value;
        }
    ),
    'Macintosh-style iPadOS Safari is recognized as iOS WebKit'
);
main::check( ( value_eq( $st->{'touchUI'}, JSON::PP::true ) ),
    'iPadOS keeps touch controls even when its primary pointer is desktop/fine' );
$c->close();
$browser->close();
main::check( ( !truth_value($errors) ),
    ( 'no JavaScript errors in Safari identity paths: ' . format_value($errors) ) );
$report = {
    'version' => '4.35.0',
    'passed'  => scalar( @{$checks} ),
    'checks'  => $checks,
    'errors'  => $errors,
    'note'    =>
'Safari identities executed in Chromium because Playwright WebKit could not be installed in this environment.'
};
$out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
