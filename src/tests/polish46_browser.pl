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

my ($a, $ap, $assets, $b, $bounce, $c, $checks, $errors, $f, $html, $i, $icons, $js, $mg, $out, $p, $pw, $r, $web);
# v4.6 focused browser checks: Q controls, weapon tuning, replay/restart, icon distinction.
$ap = {};
$a = do { my %args = ('output' => 'test-output/polish46'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl polish46_browser.pl --output
'; if ($help) { print 'Usage: perl polish46_browser.pl --output
'; exit 0; }  \%args; };
$r = path($0)->absolute->parent(2);
$web = $r->child('web');
$assets = asset_directory($web);
$out = path($a->{'output'});
$out->mkpath;
$html = replace_text(replace_re('<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8), '</head>', ((('<style>' . $assets->child('theme.css')->slurp_utf8) . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location,window.__history);') . substr($js, ($i + 4)));
$checks = [];
$errors = [];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
$c = $b->newContext({viewport => {'width' => 390, 'height' => 844}, hasTouch => JSON::PP::true, isMobile => JSON::PP::true, colorScheme => 'dark'});
$p = $c->newPage();
capture_event($p, 'pageerror', $errors, '(e) => String(e)');
$p->setContent($html);
evaluate_js($p, '()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={\'leqra.name\':\'ALPHA\',\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}');
for $f (@{['theme.js', 'netcode.js']}) {
    $p->addScriptTag({content => $assets->child($f)->slurp_utf8});
}
$p->addScriptTag({content => $js});
wait_js($p, 'window.__test&&leqra.version===\'4.6.0\'');
main::check((value_eq(evaluate_js($p, '__test.bindings[0].fire'), 'KeyQ')), 'Player 1 default Fire is Q');
main::check((contains_value($p->locator('#manualContent')->innerText(), 'Q / SPACE')), 'single-player Space alias is retained with Q');
evaluate_js($p, '__test.setWorld({width:1344,height:1176,cols:16,rows:14,walls:[]});const t=__test.tanks[0];t.cooldown=0;__test.grantPower(t,\'rapid\');__test.fire(t)');
$mg = evaluate_js($p, '({life:__test.bullets[0].life,speed:Math.hypot(__test.bullets[0].vx,__test.bullets[0].vy),trail:__test.bullets[0].trail.length})');
main::check(((abs(((28 + ($mg->{'life'} * $mg->{'speed'})) - (1344 + 1176))) < 1e-06)), 'Machine gun has half-perimeter total range including the muzzle path');
evaluate_js($p, 'const t=__test.tanks[0];t.invulnerable=0;__test.hurt(t,{owner:t.id,kind:\'rapid\'})');
main::check(evaluate_js($p, '__test.tanks[0].alive'), 'Machine gun cannot damage its sender');
evaluate_js($p, '()=>{__test.clearBullets();__test.setWorld({width:1344,height:1176,cols:16,rows:14,walls:[{x:-4,y:-4,w:8,h:1184,axis:\'v\',line:0},{x:80,y:-4,w:8,h:1184,axis:\'v\',line:84}]});__test.addBullet({id:991,owner:7,kind:\'rapid\',x:42,y:42,vx:846,vy:0,r:3.5/3,age:0,life:(1344+1176-28)/846,color:\'#fff\',bounces:0,trail:[],dead:false});for(let i=0;i<290;i++)__test.updateBullets(1/120)}');
$bounce = evaluate_js($p, '({dead:__test.bullets[0]?.dead??true,bounces:__test.bullets[0]?.bounces??0,life:__test.bullets[0]?.life??0,trail:__test.bullets[0]?.trail?.length??-1})');
main::check((do { my $boolean_value = (!truth_value($bounce->{'dead'})); truth_value($boolean_value) ? (($bounce->{'bounces'} > 22)) : $boolean_value }), 'Machine gun range survives the old 22-bounce shell ceiling');
main::check((value_eq($bounce->{'trail'}, 0)), 'Machine gun skips unused trail-history allocation');
evaluate_js($p, 'for(let i=0;i<80;i++)__test.updateBullets(1/120)');
main::check((value_eq(evaluate_js($p, '__test.bullets.length'), 0)), 'Machine gun expires at its half-perimeter path budget');
evaluate_js($p, '__test.clearBullets();const t=__test.tanks[0];t.cooldown=0;__test.grantPower(t,\'grenade\');__test.fire(t)');
main::check(((abs((evaluate_js($p, '__test.bullets[0].life') - 10)) < 1e-09)), 'Grenade fuse is ten seconds');
$icons = evaluate_js($p, '()=>{function pix(k){const c=document.createElement(\'canvas\');c.width=c.height=32;const x=c.getContext(\'2d\');x.translate(16,16);__test.powerIcon(k,x);return Array.from(x.getImageData(0,0,32,32).data)}const a=pix(\'laser\'),b=pix(\'scatter\');let d=0;for(let i=0;i<a.length;i++)d+=Math.abs(a[i]-b[i]);return d;}');
main::check((($icons > 5000)), 'Laser icon is clearly distinct from Shotgun icon');
evaluate_js($p, '__test.startRound();__test.setPhase(\'playing\');document.getElementById(\'pauseBtn\').click()');
main::check((!truth_value($p->locator('#restartLocalBtn')->isHidden())), 'local pause menu shows Restart match');
$p->locator('#restartLocalBtn')->click();
main::check((value_eq(evaluate_js($p, '__test.phase'), 'countdown')), 'Restart match immediately starts the same local setup');
evaluate_js($p, '__test.setPhase(\'matchOver\');__test.showVictory(0)');
main::check((!truth_value($p->locator('#victoryAgainBtn')->isHidden())), 'win popup shows Play Again');
$p->locator('#victoryAgainBtn')->click();
main::check((value_eq(evaluate_js($p, '__test.phase'), 'countdown')), 'Play Again immediately starts another local match');
main::check((!truth_value($errors)), ('no uncaught browser errors: ' . format_value($errors)));
$p->screenshot({path => format_value($out->child('v46-mobile.png'))});
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(json_text({'version' => '4.6.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors}, 1));
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
