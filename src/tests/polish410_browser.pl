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

my ($a, $ap, $assets, $avoid, $b, $bounds, $c, $checks, $durations, $errors, $f, $ghost, $html, $i, $js, $life, $out, $p, $pw, $r, $v, $web);
# v4.10 focused browser checks: stable Ghost HUD, 10s powers, 30s pickups, Shotgun icon, grenade-team avoidance.
$ap = {};
$a = do { my %args = ('output' => 'test-output/polish410'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl polish410_browser.pl --output
'; if ($help) { print 'Usage: perl polish410_browser.pl --output
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
$c = $b->newContext({viewport => {'width' => 390, 'height' => 844}, colorScheme => 'dark'});
$p = $c->newPage();
capture_event($p, 'pageerror', $errors, '(e) => String(e)');
$p->setContent($html);
evaluate_js($p, '()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={\'leqra.name\':\'ALPHA\',\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}');
for $f (@{['theme.js', 'netcode.js']}) {
    $p->addScriptTag({content => $assets->child($f)->slurp_utf8});
}
$p->addScriptTag({content => $js});
wait_js($p, 'window.__test&&leqra.version===\'4.10.0\'');
$ghost = evaluate_js($p, '()=>{const t=__test.tanks[0];__test.setPhase(\'playing\');Object.assign(t,{x:100,y:100,alive:true,ghostTime:10,power:null,cooldown:.2,cooldownTotal:.34,shield:0});__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});__test.updateCombatFeedback(true);const before=document.querySelector(\'#cooldownFill1\').style.transform;__test.setWorld({width:504,height:420,cols:6,rows:5,walls:[{x:90,y:80,w:20,h:50,axis:\'v\',line:100}]});__test.updateCombatFeedback(true);return{before,inside:document.querySelector(\'#cooldownFill1\').style.transform,text:document.querySelector(\'#cooldownText1\').textContent};}');
main::check((value_eq($ghost->{'text'}, 'IN WALL, MOVE TO FIRE')), 'Ghost wall block keeps IN WALL text');
main::check((do { my $boolean_value = (value_eq($ghost->{'before'}, $ghost->{'inside'})); truth_value($boolean_value) ? (!value_eq($ghost->{'inside'}, 'scaleX(0)')) : $boolean_value }), 'Ghost wall crossing does not gray/empty cooldown indicator');
$durations = evaluate_js($p, '()=>{const kinds=[\'shield\',\'speed\',\'scope\',\'ghost\',\'rapid\',\'scatter\',\'homing\',\'grenade\',\'laser\',\'cannon\'],t=__test.tanks[0],out={};for(const k of kinds){Object.assign(t,{shield:0,shieldCharges:0,speedTime:0,speedStacks:0,scopeTime:0,ghostTime:0,power:null,powerTime:0,charges:0,cooldown:0,cooldownTotal:0});__test.grantPower(t,k);out[k]=k===\'shield\'?t.shield:k===\'speed\'?t.speedTime:k===\'scope\'?t.scopeTime:k===\'ghost\'?t.ghostTime:t.powerTime;}return out;}');
main::check(!scalar(grep { my $v = $_; !(((abs(($v - 10)) < 1e-09))) } @{[values %{$durations}]}), 'all timed power-up effects use 10 seconds');
$life = evaluate_js($p, '()=>{__test.pickups.length=0;__test.spawnPower();return __test.pickups[0]?.life}');
main::check(((abs(($life - 30)) < 1e-09)), 'new uncollected pickups use 30-second lifetime');
$bounds = evaluate_js($p, '()=>{const cv=document.createElement(\'canvas\');cv.width=cv.height=40;const c=cv.getContext(\'2d\');c.translate(20,20);__test.powerIcon(\'scatter\',c);const d=c.getImageData(0,0,40,40).data;let x0=40,x1=-1,y0=40,y1=-1;for(let y=0;y<40;y++)for(let x=0;x<40;x++)if(d[(y*40+x)*4+3]){x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);}return{w:x1-x0+1,h:y1-y0+1};}');
main::check((($bounds->{'w'} > ($bounds->{'h'} * 1.5))), 'Shotgun icon has a clearly horizontal silhouette');
$avoid = evaluate_js($p, '()=>{const r={...__test.currentRules(),mode:\'elimination\',teamMode:\'teams\',friendlyFire:false};__test.setLocalRules(r);const ts=__test.tanks,t=ts[0],ally=ts[1],enemy=ts[2];Object.assign(t,{x:100,y:210,angle:0,r:17,team:1,difficulty:\'easy\',ghostTime:0});Object.assign(ally,{x:60,y:210,team:1});Object.assign(enemy,{x:420,y:210,team:2});const ctrl={angle:0,drive:1},d={speed:89,turn:2.8};const trial=owner=>{__test.clearBullets();__test.addBullet({id:owner+10,owner,kind:\'grenade\',x:150,y:210,vx:0,vy:0,r:6,life:9,dead:false});return __test.chooseGrenadeAvoid(t,ctrl,d)};const friendly=trial(ally.id),own=trial(t.id),hostile=trial(enemy.id);__test.currentRules().friendlyFire=true;const friendlyFF=trial(ally.id);return{friendly,own,hostile,friendlyFF};}');
main::check((!defined($avoid->{'friendly'})), 'bot ignores harmless friendly grenade when friendly fire is off');
main::check((defined($avoid->{'own'})), 'bot avoids its own grenade');
main::check((defined($avoid->{'hostile'})), 'bot avoids enemy grenade');
main::check((defined($avoid->{'friendlyFF'})), 'bot avoids friendly grenade when friendly fire is on');
main::check((!truth_value($errors)), ('no uncaught browser errors: ' . format_value($errors)));
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(json_text({'version' => '4.10.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'shotgunBounds' => $bounds, 'durations' => $durations}, 1));
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
