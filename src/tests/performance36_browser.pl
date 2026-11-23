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
    $assets, $b, $calls, $errors, $frames, $html, $i,      $js, $label,  $on,
    $out,    $p, $pw,    $result, $root,   $t,    $trials, $v,  $values, $web
);

# Controlled Canvas2D sprite-cache A/B. Not a GPU timer or cross-device FPS promise.
# Run: perl tests/performance36_browser.pl PROJECT_ROOT OUTPUT
$root = path( [ $0, @ARGV ]->[1] )->absolute;
$out  = path( [ $0, @ARGV ]->[2] );
$out->mkpath;
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$p      = $b->newPage( { viewport => { 'width' => 1365, 'height' => 950 } } );
$errors = [];
capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
$web    = $root->child('web');
$assets = asset_directory($web);
$html   = replace_re( '<link[^>]*>',                         '', $web->child('index.html')->slurp_utf8 );
$html   = replace_re( '<script src="[^"]+" defer></script>', '', $html );
$html   = replace_text( $html, '</head>',
    ( ( '<style>' . $assets->child('style.css')->slurp_utf8 ) . '</style></head>' ) );
$p->setContent($html);
evaluate_js( $p,
'window.__location=new URL(\'http://game.test/?test=1\');const store={\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>store[k]||null,setItem:(k,v)=>store[k]=v,removeItem:k=>delete store[k]}})'
);
$js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1 );
$i  = rindex( $js, '})()' );
$js = ( ( substr( $js, 0, $i - 0 ) . '})(window.__location);' ) . substr( $js, ( $i + 4 ) ) );
$p->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
$p->addScriptTag( { content => $js } );
evaluate_js( $p,
'()=>{let seed=360;Math.random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};const T=__test;T.setLocalRules({...T.currentRules(),mode:\'koth\',mapSize:\'huge\',teamMode:\'ffa\',timeLimit:600,scoreTarget:300});while(leqra.getState().room.players.length<8)T.addRoomSeat(\'bot\');}'
);
$p->locator('#startRoomBtn')->click();
wait_js( $p, 'leqra.getState().phase==="playing"' );
evaluate_js( $p,
'()=>{__test.setPhase(\'paused\');__test.clearBullets();for(const t of __test.tanks){t.alive=true;t.invulnerable=0;t.speedTime=0;t.shield=0;t.angle=t.id*.51;t.track=2*(t.id%4);}__test.render();}'
);
$calls = evaluate_js( $p,
'()=>{const T=__test,c=document.querySelector(\'#arena\').getContext(\'2d\'),methods=[\'beginPath\',\'moveTo\',\'lineTo\',\'arc\',\'arcTo\',\'fill\',\'stroke\',\'fillRect\',\'drawImage\',\'measureText\'],originals={},result={};let counts={};for(const k of methods){originals[k]=c[k];c[k]=function(...args){counts[k]=(counts[k]||0)+1;return originals[k].apply(this,args)}}for(const on of [false,true]){T.setHullCache(on);T.render();counts={};T.render();result[on?\'cached\':\'vector\']={...counts};}for(const k of methods)c[k]=originals[k];return result;}'
);
$trials = evaluate_js( $p,
'async()=>{const T=__test,out=[];for(const on of [false,true,true,false,false,true,true,false]){T.setHullCache(on);for(let i=0;i<15;i++)T.render();await new Promise(r=>setTimeout(r,40));const n=150,t=performance.now();for(let i=0;i<n;i++)T.render();out.push({cached:on,frames:n,submission_ms:(performance.now()-t)/n});await new Promise(r=>setTimeout(r,80));}return out;}'
);
$frames = {};

for $on ( @{ [ JSON::PP::false, JSON::PP::true ] } ) {
    evaluate_js( $p, '(v)=>__test.setHullCache(v)', $on );
    $values = evaluate_js( $p,
'()=>new Promise(resolve=>{const intervals=[];let last=0,start=0;function f(t){if(!start)start=t;if(last)intervals.push(t-last);last=t;if(t-start<6000)requestAnimationFrame(f);else resolve(intervals);}requestAnimationFrame(f);})'
    );
    $frames->{ ( truth_value($on) ? 'cached' : 'vector' ) } = {
        'frames'           => scalar( @{$values} ),
        'average_frame_ms' => mean($values),
        'p95_frame_ms'     => sorted_values($values)->[ int( ( 0.95 * scalar( @{$values} ) ) ) ],
        'over_25ms'        => sum( @{ [ map { my $v = $_; ( ( $v > 25 ) ) } @{$values} ] } )
    };
}
$result = {
    'version'  => '3.6.0',
    'scenario' =>
'Same frozen 8-tank 14x12 scene, 1365x950 desktop, DPR 1, Chromium headless; only hull-cache switch changes. Both use bounded text-width caching. 8 alternating 150-render batches; synchronous JS/Canvas submission, not GPU completion. Separate 6-second RAF samples.',
    'main_canvas_calls'    => $calls,
    'trials'               => $trials,
    'median_submission_ms' => {
        map {
            my ( $label, $on ) = @{$_};
            $label => median(
                [
                    map {
                        my $t = $_;
                        truth_value( ( value_eq( $t->{'cached'}, $on ) ) )
                          ? ( $t->{'submission_ms'} )
                          : ()
                    } @{$trials}
                ]
            )
        } @{ [ [ 'vector', JSON::PP::false ], [ 'cached', JSON::PP::true ] ] }
    },
    'raf'    => $frames,
    'cache'  => evaluate_js( $p, '__test.renderStats' ),
    'errors' => $errors
};
$p->screenshot( { path => format_value( $out->child('eight-tank-cache.png') ) } );
$out->child('report.json')->spew_utf8( json_text( $result, 1 ) );
print( join( " ", json_text( $result, 1 ) ), "\n" );
$b->close();
