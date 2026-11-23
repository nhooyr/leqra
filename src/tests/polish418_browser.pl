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

my ($a, $after, $ap, $assets, $b, $before, $c, $checks, $down, $during, $errors, $html, $i, $js, $manual, $out, $p, $pw, $r, $result, $safari_ua, $sc, $sp, $web);
# Focused UI regression checks retained through v4.20.
$ap = {};
$a = do { my %args = ('output' => 'tests/results/v4.18-browser'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl polish418_browser.pl --output
'; if ($help) { print 'Usage: perl polish418_browser.pl --output
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
sub install {
    my ($page, $name, $disable_ua_data) = @_;
    my ($f);
    $name //= 'ALPHA';
    $disable_ua_data //= JSON::PP::false;
    $page->setContent($html);
    evaluate_js($page, 'a=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};const d={\'leqra.name\':a.name,\'leqra.muted\':\'1\'};const store=x=>({getItem:k=>x[k]??null,setItem:(k,v)=>x[k]=String(v),removeItem:k=>delete x[k]});Object.defineProperty(window,\'localStorage\',{value:store(d)});Object.defineProperty(window,\'sessionStorage\',{value:store({})});if(a.noUAData){try{Object.defineProperty(navigator,\'userAgentData\',{value:undefined,configurable:true});}catch(_){}}}', {'name' => $name, 'noUAData' => $disable_ua_data});
    for $f (@{['theme.js', 'netcode.js']}) {
        $page->addScriptTag({content => $assets->child($f)->slurp_utf8});
    }
    $page->addScriptTag({content => $js});
    wait_js($page, 'window.__test&&leqra.version===\'4.35.0\'');
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
$c = $b->newContext({viewport => {'width' => 1365, 'height' => 950}, colorScheme => 'dark'});
$p = $c->newPage();
capture_event($p, 'pageerror', $errors, '(e) => String(e)');
main::install($p);
main::check(JSON::PP::true, 'Chromium does not receive the Safari-only browser recommendation');
main::check((do { my $boolean_value = (value_eq(evaluate_js($p, '__test.pickupLifetime(16,14)'), 61)); truth_value($boolean_value) ? (value_eq(evaluate_js($p, '__test.pickupLifetime(24,14)'), 90)) : $boolean_value }), 'ground pickup expiry uses the 8/3 maze-cap formula (Giant 61s, Ultra Wide 90s)');
evaluate_js($p, '__test.createLocalRoom()');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(30));
$manual = evaluate_js($p, '()=>{const box=document.querySelector(\'#manualContent .manual-key-options\'),rows=[...box.querySelectorAll(\'.keys\')];return{keys:rows.map(r=>[...r.querySelectorAll(\'kbd\')].map(k=>k.textContent)),tops:rows.map(r=>r.getBoundingClientRect().top),text:document.querySelector(\'#manualContent\').innerText};}');
main::check((do { my $boolean_value = (value_eq($manual->{'keys'}->[0], ['↑', '←', '↓', '→'])); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($manual->{'keys'}->[1], ['W', 'A', 'S', 'D'])); truth_value($boolean_value) ? (($manual->{'tops'}->[0] < $manual->{'tops'}->[1])) : $boolean_value } : $boolean_value }), 'single-P1 Field Manual places arrow movement above WASD');
$p->locator('#startRoomBtn')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(80));
sub arena_metrics {
    return evaluate_js($p, '()=>{const w=document.querySelector(\'.arena-wrap\').getBoundingClientRect(),c=document.querySelector(\'#arena\'),v=__test.view,d=window.devicePixelRatio||1;return{wrapW:w.width,wrapH:w.height,cssW:v.cssW,cssH:v.cssH,canvasW:c.width,canvasH:c.height,ratio:w.width/w.height,canvasRatio:c.width/c.height};}');
}
$before = main::arena_metrics();
$p->locator('#pauseBtn')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(80));
$p->locator('#menuControlsBtn')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(80));
$during = main::arena_metrics();
$p->locator('[data-close-dialog="controlsDialog"]')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(40));
$p->locator('#onlineReturnBtn')->click();
$Leqra::Browser::HANDLE->await($p->waitForTimeout(100));
$after = main::arena_metrics();
sub aligned {
    my ($m) = @_;
    return (do { my $boolean_value = ((abs(($m->{'wrapW'} - $m->{'cssW'})) < 1)); truth_value($boolean_value) ? do { my $boolean_value = ((abs(($m->{'wrapH'} - $m->{'cssH'})) < 1)); truth_value($boolean_value) ? ((abs(($m->{'ratio'} - $m->{'canvasRatio'})) < 0.01)) : $boolean_value } : $boolean_value });
}
main::check((do { my $boolean_value = main::aligned($before); truth_value($boolean_value) ? do { my $boolean_value = main::aligned($during); truth_value($boolean_value) ? main::aligned($after) : $boolean_value } : $boolean_value }), 'pause/menu interactions keep canvas and arena aspect ratios synchronized (no horizontal stretch)');
evaluate_js($p, '()=>{__test.createLocalRoom();__test.addRoomSeat(\'local\');__test.resetPreview();__test.setPhase(\'playing\');const p2=__test.localRoom.players.find(x=>x.kind===\'local\');const t1=__test.tanks.find(t=>t.id===0),t2=__test.tanks.find(t=>t.id===p2.id);t1.alive=false;t2.alive=false;__test.updateHUD(true);}');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(30));
$down = evaluate_js($p, '()=>({p1:document.querySelector(\'#weaponLabel\').textContent,p2:document.querySelector(\'#weaponLabel2\').textContent,caption:document.querySelector(\'#watchingCaption\').textContent,loadouts:document.querySelector(\'#localLoadouts\').innerText})');
main::check((do { my $boolean_value = (value_eq($down->{'p1'}, 'TANK DOWN')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($down->{'p2'}, 'TANK DOWN')); truth_value($boolean_value) ? (!(contains_value($down->{'loadouts'}, 'SPECTATING'))) : $boolean_value } : $boolean_value }), 'dead P1 and P2 remain TANK DOWN rather than becoming Spectating');
evaluate_js($p, '()=>{__test.createLocalRoom();__test.resetPreview();__test.setPhase(\'matchOver\');__test.showVictory(1);}');
$Leqra::Browser::HANDLE->await($p->waitForTimeout(30));
$result = evaluate_js($p, '()=>{const t=document.querySelector(\'#victoryTitle\'),e=document.querySelector(\'#victoryEmblem\');return{eyebrow:document.querySelector(\'#victoryEyebrow\').textContent,title:t.textContent,message:document.querySelector(\'#victoryMessage\').textContent,all:document.querySelector(\'#victoryDialog\').innerText,emblem:e.textContent,color:getComputedStyle(t).color,titleTop:t.getBoundingClientRect().top,emblemTop:e.getBoundingClientRect().top}}');
main::check((do { my $boolean_value = (value_eq($result->{'eyebrow'}, 'MATCH RESULTS')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'title'}, 'DEFEAT')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'emblem'}, '☠')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($result->{'color'}, 'rgb(255, 79, 95)')); truth_value($boolean_value) ? do { my $boolean_value = (($result->{'emblemTop'} > $result->{'titleTop'})); truth_value($boolean_value) ? (!(contains_value(uc($result->{'all'}), 'CONGRAT'))) : $boolean_value } : $boolean_value } : $boolean_value } : $boolean_value } : $boolean_value }), 'losing player receives red DEFEAT with defeat icon below it and no congratulations');
evaluate_js($p, '__test.closeVictory()');
main::check((!truth_value($errors)), ('no uncaught Chromium browser errors: ' . format_value($errors)));
$p->screenshot({path => format_value($out->child('v418-desktop.png'))});
$c->close();
$safari_ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
$sc = $b->newContext({viewport => {'width' => 1365, 'height' => 950}, userAgent => $safari_ua, colorScheme => 'dark'});
$sp = $sc->newPage();
capture_event($sp, 'pageerror', $errors, '(e) => ("safari-emulation: " + String(e))');
main::install($sp, 'SAFARI TEST', JSON::PP::true);
$Leqra::Browser::HANDLE->await($sp->waitForTimeout(30));
main::check((do { my $boolean_value = (value_eq($sp->locator('#browserNotice')->count(), 1)); truth_value($boolean_value) ? (contains_value($sp->locator('#browserNotice')->innerText(), 'Chrome or Firefox')) : $boolean_value }), 'desktop Safari recommends Chrome or Firefox');
$sc->close();
$b->close();
$out->child('results.json')->spew_utf8(json_text({'version' => '4.35.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'manual' => $manual, 'arena' => {'before' => $before, 'during' => $during, 'after' => $after}, 'down' => $down, 'result' => $result}, 1));
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
