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

my ($args, $assets, $b, $c, $cap, $checks, $e, $errors, $geometry, $h, $html, $i, $js, $mobile, $mode, $n, $name, $out, $p, $p2, $pa, $pixels, $pw, $rate, $result, $root, $s, $sizes, $start, $stored, $w, $weapons, $web);
# v3.8 map density, Scope geometry/HUD, icons and settings regression.
# Uses exact assets with synthetic URL/storage and deterministic simulation stepping.
$pa = {};
$args = do { my %args = ('output' => 'test-output/scope38', 'browser' => '/usr/bin/chromium'); my $help; GetOptions('output=s' => \$args{'output'}, 'browser=s' => \$args{'browser'}, 'help|h' => \$help) or die 'Usage: perl scope38_browser.pl --output --browser
'; if ($help) { print 'Usage: perl scope38_browser.pl --output --browser
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub check {
    my ($x, $s) = @_;
    assert_ok($x, $s);
    push(@{$checks}, $s);
    print(join(" ", 'PASS', $s), "\n");
}
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script src="[^"]+" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
sub load {
    my ($c, $data) = @_;
    my ($p);
    $data //= undef;
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, 'data=>{window.__location=new URL(\'http://game.test/?test=1\');window.__store=data;
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,\'localStorage\',{value:store(data)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});window.requestAnimationFrame=()=>0;
 }', (do { my $boolean_value = $data; truth_value($boolean_value) ? $boolean_value : {'leqra.muted' => '1'} }));
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra && window.__test');
    return $p;
}
$sizes = [['compact', 7, 7, 2, 5], ['standard', 9, 8, 3, 7], ['large', 12, 10, 4, 12], ['huge', 14, 12, 5, 17], ['giant', 16, 14, 6, 23]];
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
eval {
    $c = $b->newContext({viewport => {'width' => 1365, 'height' => 950}});
    $p = main::load($c);
    main::check((value_eq(evaluate_js($p, 'leqra.version'), '3.9.0')), 'Version 3.9.0 starts without errors');
    main::check(evaluate_js($p, 'leqra.getState().rules.mapSize===\'large\' && leqra.getState().rules.pickupRate===\'superfast\''), '12x10 and Super fast defaults retained');
    main::check(evaluate_js($p, 'leqra.getState().rules.weapons.includes(\'scope\') && leqra.getState().rules.weapons.length===9'), 'Scope remains included with all nine default pickups');
    $p->locator('#roomRulesBtn')->click();
    main::check((value_eq($p->locator('#roomMapSize option')->count(), 6)), 'All six map choices visible');
    main::check($p->locator('[data-weapon-toggle="scope"]')->isChecked(), 'Host can enable/disable Scope in rules');
    for my $item (@{$sizes}) {
        my $tuple_32_6 = $item;
        my $name = $tuple_32_6->[0];
        my $w = $tuple_32_6->[1];
        my $h = $tuple_32_6->[2];
        my $start = $tuple_32_6->[3];
        my $cap = $tuple_32_6->[4];
        $p->locator('[data-close-dialog="rulesDialog"]')->click();
        $p->locator('#roomMapSize')->selectOption($name);
        $p->locator('#roomRulesBtn')->click();
        main::check((index($p->locator('#rule-pickup-density')->innerText(), ($start . ' starting power-ups, ' . $cap . ' maximum')) == 0), ($name . ' live density explanation'));
        $p->locator('#applyRulesBtn')->click();
        my $s = evaluate_js($p, 'leqra.getState()');
        main::check((value_eq([$s->{'world'}->{'cols'}, $s->{'world'}->{'rows'}, $s->{'pickupCount'}], [$w, $h, $start])), ($name . ' local preview dimensions and starts'));
        $p->locator('#roomRulesBtn')->click();
    }
    $p->screenshot({path => format_value($out->child('rules-1365x950.png'))});
    $p->locator('[data-close-dialog="rulesDialog"]')->click();
    $p->locator('#roomPresetsBtn')->click();
    $p->locator('#presetName')->fill('Giant scope game');
    $p->locator('#savePresetBtn')->click();
    $stored = evaluate_js($p, '__store');
    $p2 = main::load($c, $stored);
    $p2->locator('#roomPresetsBtn')->click();
    $p2->locator('#presetSelect')->selectOption('saved:0');
    $p2->locator('#loadPresetBtn')->click();
    main::check(evaluate_js($p2, 'leqra.getState().rules.mapSize===\'giant\' && leqra.getState().rules.weapons.includes(\'scope\')'), '16x14 + Scope survive saved preset reload');
    $p2->close();
    $p->locator('[data-close-dialog="presetsDialog"]')->click();
    for $mode (@{['elimination', 'ctf', 'koth']}) {
        for my $item (@{$sizes}) {
            my $tuple_44_7 = $item;
            my $name = $tuple_44_7->[0];
            my $w = $tuple_44_7->[1];
            my $h = $tuple_44_7->[2];
            my $start = $tuple_44_7->[3];
            my $cap = $tuple_44_7->[4];
            my $result = evaluate_js($p, '({mode,name})=>{const T=__test;T.setPhase(\'menu\');
     T.applyLocalPreset({rules:{...T.defaultRoomRules(),mode,teamMode:\'teams\',mapSize:name,weapons:[\'scope\'],timeLimit:600},roster:Array.from({length:8},(_,i)=>({kind:i===0?\'human\':i===1?\'local\':\'bot\',name:\'P\'+i,difficulty:\'normal\',team:1+i%2}))});T.startRound();
     const initial=T.pickups.length;T.setPhase(\'playing\');for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=999;}
     for(let i=0;i<119;i++)T.update(1/120);const before=T.pickups.length;for(let i=0;i<2;i++)T.update(1/120);const after=T.pickups.length;
     for(let i=0;i<300;i++)T.spawnPower();const cap=T.pickups.length;
     const safe=T.pickups.every((p,i)=>T.pickups.every((q,j)=>i===j||Math.hypot(p.x-q.x,p.y-q.y)>84*1.1)&&T.tanks.every(t=>!t.alive||Math.hypot(p.x-t.x,p.y-t.y)>84*.85));
     const onlyScope=T.pickups.every(p=>p.type===\'scope\');T.setPhase(\'menu\');return{initial,before,after,cap,safe,onlyScope};}', {'mode' => $mode, 'name' => $name});
            main::check((do { my $boolean_value = (value_eq($result->{'initial'}, $start)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'before'}, $start)); truth_value($boolean_value) ? (value_eq($result->{'after'}, ($start + 1))) : $boolean_value } : $boolean_value }), ($mode . '/' . $name . ': initial supply and first-second boundary'));
            main::check((do { my $boolean_value = (value_eq($result->{'cap'}, $cap)); truth_value($boolean_value) ? do { my $boolean_value = $result->{'safe'}; truth_value($boolean_value) ? $result->{'onlyScope'} : $boolean_value } : $boolean_value }), ($mode . '/' . $name . ': exact cap, safe separation, scope-only filter'));
        }
    }
    for my $item (@{[[[], 'superfast'], [['scope'], 'off']]}) {
        my $tuple_54_6 = $item;
        my $weapons = $tuple_54_6->[0];
        my $rate = $tuple_54_6->[1];
        my $n = evaluate_js($p, '({weapons,rate})=>{const T=__test;T.setPhase(\'menu\');T.setLocalRules({...T.defaultRoomRules(),mapSize:\'giant\',weapons,pickupRate:rate});T.startRound();for(let i=0;i<100;i++)T.spawnPower();return T.pickups.length;}', {'weapons' => $weapons, 'rate' => $rate});
        main::check((value_eq($n, 0)), ('Disabled pickup rule respected: ' . $rate . '/' . $weapons));
    }
    $result = evaluate_js($p, '()=>{const T=__test;T.setPhase(\'menu\');T.setLocalRules({...T.defaultRoomRules(),mapSize:\'giant\'});T.startRound();T.setPhase(\'playing\');T.clearBullets();T.pickups.length=0;for(const t of T.tanks){t.human=true;t.invulnerable=99;}
   const t=T.tanks[0];T.grantPower(t,\'laser\');T.grantPower(t,\'speed\');T.grantPower(t,\'shield\');T.pickups.push({x:t.x,y:t.y,type:\'scope\',life:19,age:0});T.update(1/120);
   const acquired={scope:t.scopeTime,power:t.power,charges:t.charges,shield:t.shield,speed:t.speedTime};t.scopeTime=1;T.grantPower(t,\'scope\');const refreshed=t.scopeTime;t.scopeTime=.001;T.update(1/120);const expired=t.scopeTime;T.grantPower(t,\'scope\');T.respawnLocalTank(t);return{acquired,refreshed,expired,respawn:t.scopeTime};}');
    main::check((do { my $boolean_value = (value_eq($result->{'acquired'}->{'scope'}, 10)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'acquired'}->{'power'}, 'laser')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'acquired'}->{'charges'}, 3)); truth_value($boolean_value) ? do { my $boolean_value = (($result->{'acquired'}->{'shield'} > 9)); truth_value($boolean_value) ? (($result->{'acquired'}->{'speed'} > 5)) : $boolean_value } : $boolean_value } : $boolean_value } : $boolean_value }), 'Actual Scope collection preserves laser, charges, shield and boost');
    main::check((do { my $boolean_value = (value_eq($result->{'refreshed'}, 10)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'expired'}, 0)); truth_value($boolean_value) ? (value_eq($result->{'respawn'}, 0)) : $boolean_value } : $boolean_value }), 'Scope refreshes without stacking, expires and resets on respawn');
    $geometry = evaluate_js($p, '()=>{const T=__test;T.setPhase(\'playing\');T.clearBullets();for(const t of T.tanks)t.alive=false;const t=T.tanks[0];Object.assign(t,{alive:true,invulnerable:99,x:300,y:210,angle:.41,scopeTime:10,power:null});
   const width=1344,height=1176;T.setWorld({cols:16,rows:14,width,height,walls:[{x:-4,y:-4,w:width+8,h:8},{x:-4,y:height-4,w:width+8,h:8},{x:-4,y:-4,w:8,h:height+8},{x:width-4,y:-4,w:8,h:height+8}]});
   const before=JSON.stringify({t,bullets:T.bullets,stats:T.matchReport});const g=T.aimingGuide(t);const total=g.points.reduce((sum,p,i)=>sum+(i?Math.hypot(p.x-g.points[i-1].x,p.y-g.points[i-1].y):0),0);const bounded=g.points.every(p=>p.x>=7.499&&p.x<=width-7.499&&p.y>=7.499&&p.y<=height-7.499);
   const unchanged=before===JSON.stringify({t,bullets:T.bullets,stats:T.matchReport});t.scopeTime=0;const normal=T.aimingGuide(t);const short=normal.points.reduce((s,p,i)=>s+(i?Math.hypot(p.x-normal.points[i-1].x,p.y-normal.points[i-1].y):0),0);
   const other=T.tanks[1];Object.assign(t,{scopeTime:10,angle:0,invulnerable:0,team:1});Object.assign(other,{alive:true,x:450,y:210,r:17,invulnerable:0,team:2});const stopped=T.aimingGuide(t);
   other.team=1;const friendly=T.aimingGuide(t);return{total,bounded,segments:g.points.length,unchanged,short,target:stopped.tank?.id,friend: friendly.tank?.id??null};}');
    main::check((do { my $boolean_value = ((abs(($geometry->{'total'} - 2520)) < 0.002)); truth_value($boolean_value) ? do { my $boolean_value = $geometry->{'bounded'}; truth_value($boolean_value) ? (($geometry->{'segments'} > 2)) : $boolean_value } : $boolean_value }), 'Scope reflects at walls with exact 2520-unit half-perimeter budget');
    main::check((do { my $boolean_value = $geometry->{'unchanged'}; truth_value($boolean_value) ? ((abs(($geometry->{'short'} - 112)) < 0.001)) : $boolean_value }), 'Guide is cosmetic and returns to original 112-unit length');
    main::check((do { my $boolean_value = (value_eq($geometry->{'target'}, 1)); truth_value($boolean_value) ? (!value_eq($geometry->{'friend'}, 1)) : $boolean_value }), 'Guide stops at opposing tank and respects friendly-fire protection');
    $c->close();
    for my $item (@{[[1365, 950], [390, 844], [320, 568], [844, 390]]}) {
        my $tuple_73_6 = $item;
        my $w = $tuple_73_6->[0];
        my $h = $tuple_73_6->[1];
        my $mobile = (do { my $boolean_value = (($w < 760)); truth_value($boolean_value) ? $boolean_value : (($h < 620)) });
        my $c = $b->newContext({viewport => {'width' => $w, 'height' => $h}, hasTouch => $mobile, isMobile => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
        my $p = main::load($c);
        my $pixels = evaluate_js($p, '()=>{const T=__test;T.renderPowerLegend();return [...document.querySelectorAll(\'.power-list canvas[data-power-icon]\')].map(e=>{const fresh=document.createElement(\'canvas\');fresh.width=e.width;fresh.height=e.height;const c=fresh.getContext(\'2d\');c.setTransform(e.width/26,0,0,e.height/26,e.width/2,e.height/2);T.powerIcon(e.dataset.powerIcon,c);return{name:e.dataset.powerIcon,match:e.toDataURL()===fresh.toDataURL()};});}');
        main::check((do { my $boolean_value = (value_eq(scalar(@{$pixels}), 9)); truth_value($boolean_value) ? !scalar(grep { my $e = $_; !($e->{'match'}) } @{$pixels}) : $boolean_value }), ($w . 'x' . $h . ': all nine legend icons pixel-match shared maze routine'));
        $p->locator('#roomMapSize')->selectOption('giant');
        wait_js($p, '(value)=>leqra.getState().rules.mapSize===value', 'giant', {});
        $p->locator('#roomRulesBtn')->click();
        $p->screenshot({path => format_value($out->child(('rules-' . $w . 'x' . $h . '.png')))});
        $p->locator('#applyRulesBtn')->click();
        evaluate_js($p, '__test.addRoomSeat(\'local\')');
        $p->locator('#startRoomBtn')->click();
        my $result = evaluate_js($p, '()=>{const T=__test;T.setPhase(\'playing\');T.clearBullets();for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=0;}
    const rect=()=>{const b=document.querySelector(\'#arenaWrap\').getBoundingClientRect();return [b.width,b.height]};T.updateHUD(true);const before=rect();
    const one=T.tanks[0],two=T.tanks.find(t=>t.localIndex===1);for(const t of [one,two])for(const k of [\'scope\',\'speed\',\'shield\',\'laser\'])T.grantPower(t,k);T.updateHUD(true);T.render();
    const after=rect(),labels=[document.querySelector(\'#buffLabel\').textContent,document.querySelector(\'#buffLabel2\').textContent];const active=[T.aimingGuide(one).points.length,T.aimingGuide(two).points.length];
    for(const t of [one,two]){t.scopeTime=0;t.speedTime=0;t.shield=0;}T.updateHUD(true);const expired=rect();for(const t of [one,two])for(const k of [\'scope\',\'speed\',\'shield\',\'laser\'])T.grantPower(t,k);T.updateHUD(true);T.render();
    return {before,after,expired,labels,active};}');
        main::check((value_eq($result->{'before'}, $result->{'after'}) && value_eq($result->{'after'}, $result->{'expired'})), ($w . 'x' . $h . ': pickup collection/expiry does not resize arena'));
        main::check(!scalar(grep { my $s = $_; !((do { my $boolean_value = (contains_value($s, 'SCP 10s')); truth_value($boolean_value) ? do { my $boolean_value = (contains_value($s, 'SPD 6s')); truth_value($boolean_value) ? (contains_value($s, 'SHD 10s')) : $boolean_value } : $boolean_value })) } @{$result->{'labels'}}), ($w . 'x' . $h . ': both pilots get independent stacked buff timers'));
        main::check(!scalar(grep { my $n = $_; !((($n >= 2))) } @{$result->{'active'}}), ($w . 'x' . $h . ': both local pilots have extended guides'));
        main::check(evaluate_js($p, 'document.documentElement.scrollWidth<=innerWidth+1'), ($w . 'x' . $h . ': no horizontal page overflow'));
        $p->screenshot({path => format_value($out->child(('scope-' . $w . 'x' . $h . '.png')))});
        $c->close();
    }
    main::check((!truth_value($errors)), 'No uncaught browser errors');
    $out->child('results.json')->spew_utf8(json_text({'version' => '3.9.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Chromium emulation, synthetic URL/storage, manual simulation stepping; no physical devices.'}, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
$b->close();
die $caught_error if $caught_error;
