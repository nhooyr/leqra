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
use Leqra::Network qw(ordered_delay_script);

my ($a, $ap, $assets, $auth, $b, $backwards, $before, $c, $checks, $code, $contexts, $delay, $errors, $f, $fills, $first, $frames, $gen, $hc, $hold, $host, $html, $i, $ids, $js, $labels, $m, $measurements, $n, $old, $out, $points, $power, $pressed, $pw, $r, $source, $t, $v, $vc, $viewer, $web, $wrapper, $x, $y);
# v4.2 real Go WebSocket firing, two local controllers, and viewer regression.
# Injected assets/Location/storage and ordered delay; real DOM, canvas, input/socket.
# The deterministic arena is provided only by the opt-in _test.go fixture.
$ap = {};
$a = do { my %args = ('url' => 'http://127.0.0.1:18042', 'output' => 'test-output/feel42-live'); my $help; GetOptions('url=s' => \$args{'url'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl feel42_live.pl --url --output
'; if ($help) { print 'Usage: perl feel42_live.pl --url --output
'; exit 0; }  \%args; };
$r = path($0)->absolute->parent(2);
$web = $r->child('web');
$assets = asset_directory($web);
$out = path($a->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
$measurements = [];
sub check {
    my ($ok, $label) = @_;
    assert_ok($ok, $label);
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
$html = replace_re('<link[^>]*>|<script src="theme.js"></script>', '', $web->child('index.html')->slurp_utf8);
$html = replace_text(replace_re('<script src="[^"]+" defer></script>', '', $html), '</head>', ((('<style>' . $assets->child('theme.css')->slurp_utf8) . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location,window.__history);') . substr($js, ($i + 4)));
$wrapper = ordered_delay_script();
$wrapper = replace_text($wrapper, 'base:60,jitter:[0,45,8,27,65,2,30,12]', 'base:90,jitter:[0,25,8,40,3,12]');
sub load {
    my ($b, $name, $w, $h, $invite) = @_;
    my ($c, $p);
    $w //= 1365;
    $h //= 950;
    $invite //= '';
    $c = $b->newContext({viewport => {'width' => $w, 'height' => $h}, isMobile => (do { my $boolean_value = (($w < 760)); truth_value($boolean_value) ? $boolean_value : (($h < 620)) }), hasTouch => (do { my $boolean_value = (($w < 760)); truth_value($boolean_value) ? $boolean_value : (($h < 620)) })});
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, 'a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__url=String(u)}};
 for(const name of [\'localStorage\',\'sessionStorage\']){const d={\'leqra.name\':a.name,\'leqra.muted\':\'1\'};Object.defineProperty(window,name,{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});}}', {'url' => (($a->{'url'} . '/?test=1') . $invite), 'name' => $name});
    evaluate_js($p, $wrapper);
    $p->addScriptTag({content => $assets->child('theme.js')->slurp_utf8});
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.__test');
    evaluate_js($p, '()=>{window.__fireRecord=false;window.__fireFrames=[];function record(at){if(__fireRecord){const s=__test.online.snapshots.at(-1);__fireFrames.push({at,phase:__test.phase,bullets:__test.bullets.map(b=>({id:b.id??-1,owner:b.owner,x:b.x,y:b.y,preview:!!b.preview,shot:b.shotSerial,pellet:b.pellet||0,age:b.age,bounces:b.bounces})),authority:s?.tanks.map(t=>({id:t.id,shot:t.shotSerial,cooldown:t.cooldown})),label:document.querySelector(\'#fireLabel\').textContent,fill:document.querySelector(\'#cooldownFill1\').style.transform,metrics:{...__test.presentationMetrics}});}requestAnimationFrame(record);}requestAnimationFrame(record);}');
    return [$p, $c];
}
sub fixture {
    my ($code, $weapon, $action, $player) = @_;
    my ($req, $res);
    $weapon //= '';
    $action //= 'setup';
    $player //= 0;
    $req = HTTP::Request->new('POST', ($a->{'url'} . '/_fixture/combat42'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'weapon' => $weapon, 'action' => $action, 'player' => $player})));
    $res = request_ok($req);
    return decode_json($res->content);
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
$contexts = [];
eval {
    my $tuple_35_2 = main::load($b, 'HOST');
    $host = $tuple_35_2->[0];
    $hc = $tuple_35_2->[1];
    push(@{$contexts}, $hc);
    $host->locator('#addLocalBtn')->click();
    $host->locator('#copyInviteBtn')->click();
    wait_js($host, 'leqra.getState().online?.connected');
    wait_js($host, '__test.online.roomData?.players.some(p=>p.kind==="local")');
    $code = evaluate_js($host, '__test.online.code');
    $ids = evaluate_js($host, '[__test.online.id,__test.online.roomData.players.find(p=>p.kind==="local").id]');
    my $tuple_37_2 = main::load($b, 'VIEWER', 390, 844, (('&room=' . $code) . '&spectate=1'));
    $viewer = $tuple_37_2->[0];
    $vc = $tuple_37_2->[1];
    push(@{$contexts}, $vc);
    $viewer->locator('#joinRoomBtn')->click();
    wait_js($viewer, 'leqra.getState().online?.spectating');
    $host->locator('#startRoomBtn')->click();
    wait_js($host, 'leqra.getState().phase===\'playing\'');
    main::check((do { my $boolean_value = (value_eq(scalar(@{$ids}), 2)); truth_value($boolean_value) ? (!value_eq($ids->[0], $ids->[1])) : $boolean_value }), 'Two independently controlled local tanks plus a real online viewer');
    for my $item (@{[['', 0.09], ['rapid', 0.43], ['scatter', 0.09], ['homing', 0.09], ['grenade', 0.09], ['cannon', 0.09], ['laser', 0.09]]}) {
        my $tuple_40_6 = $item;
        my $power = $tuple_40_6->[0];
        my $hold = $tuple_40_6->[1];
        my $gen = main::fixture($code, $power)->{'generation'};
        wait_js($host, '(g)=>__test.online.generation===g', $gen, {});
        wait_js($viewer, '(g)=>__test.online.generation===g', $gen, {});
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(160));
        evaluate_js($host, 'window.__fireFrames=[];window.__fireRecord=true;window.__pressedAt=performance.now()');
        $host->keyboard()->down('f');
        $host->keyboard()->down('Space');
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(int(($hold * 1000))));
        $host->keyboard()->up('f');
        $host->keyboard()->up('Space');
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(1100));
        evaluate_js($host, 'window.__fireRecord=false');
        my $frames = evaluate_js($host, '__fireFrames');
        my $pressed = evaluate_js($host, '__pressedAt');
        push(@{$measurements}, {'power' => (do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }), 'pressedAt' => $pressed, 'frames' => $frames});
        my $m = evaluate_js($host, '__test.presentationMetrics');
        main::check((do { my $boolean_value = (($m->{'previews'} >= 2)); truth_value($boolean_value) ? (($m->{'confirmed'} >= 0)) : $boolean_value }), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': both local firing responses predicted'));
        main::check((($m->{'suppressedSounds'} >= 2)), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': accepted shots do not replay local firing sounds'));
        my $auth = evaluate_js($host, '(ids)=>__test.online.snapshots.at(-1).tanks.filter(t=>ids.includes(t.id)).map(t=>t.shotSerial)', $ids);
        main::check((do { my $boolean_value = (value_eq(scalar(@{$auth}), 2)); truth_value($boolean_value) ? !scalar(grep { my $n = $_; !((($n >= 1))) } @{$auth}) : $boolean_value }), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': Go confirms both independent shots'));
        if (truth_value((!(contains_value(['laser', 'rapid'], $power))))) {
            my $first = ([map { my $f = $_; truth_value(scalar(grep { my $x = $_; (do { my $boolean_value = (value_eq($x->{'owner'}, $ids->[0])); truth_value($boolean_value) ? $x->{'preview'} : $boolean_value }) } @{$f->{'bullets'}})) ? ($f) : () } @{$frames}]->[0] // undef);
            main::check((do { my $boolean_value = (defined($first)); truth_value($boolean_value) ? !scalar(grep { my $t = $_; !((!((value_eq($t->{'id'}, $ids->[0]))) || (value_eq($t->{'shot'}, 0)))) } @{$first->{'authority'}}) : $boolean_value }), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': visual projectile exists before server acknowledgement'));
            my $delay = ($first->{'at'} - $pressed);
            main::check((($delay < 100)), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': first-frame response (' . sprintf('%.1f', $delay) . ' ms under injected delay)'));
        }
        if (truth_value((contains_value(['', 'cannon'], $power)))) {
            my $points = [];
            for my $f (@{$frames}) {
                my $x = ([map { my $x = $_; truth_value((do { my $boolean_value = (value_eq($x->{'owner'}, $ids->[0])); truth_value($boolean_value) ? do { my $boolean_value = (value_eq(($x->{'shot'} // undef), 1)); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($x->{'pellet'}, 0)); truth_value($boolean_value) ? (value_eq($x->{'bounces'}, 0)) : $boolean_value } : $boolean_value } : $boolean_value })) ? ($x) : () } @{$f->{'bullets'}}]->[0] // undef);
                if (truth_value($x)) {
                    push(@{$points}, $x->{'x'});
                }
            }
            my $backwards = sum(@{[map { my ($x, $y) = @{$_}; (($y < ($x - 0.5))) } @{[map { my $i = $_; [$points->[$i], array_slice($points, 1, undef)->[$i]] } 0 .. min($#{$points}, $#{array_slice($points, 1, undef)})]}]});
            main::check((value_eq($backwards, 0)), ((do { my $boolean_value = $power; truth_value($boolean_value) ? $boolean_value : 'standard' }) . ': no projectile rewind on server confirmation'));
        }
        if (truth_value((value_eq($power, 'grenade')))) {
            my $before = evaluate_js($host, '__test.online.snapshots.at(-1).events.filter(e=>e.type==="blast").length');
            $host->keyboard()->press('f');
            $Leqra::Browser::HANDLE->await($host->waitForTimeout(500));
            main::check(evaluate_js($host, '(id)=>!__test.online.snapshots.at(-1).bullets.some(b=>b.owner===id&&b.kind==="grenade")', $ids->[0]), 'Fresh Fire press remotely detonates P1 grenade after prediction');
            main::check(evaluate_js($host, '(id)=>__test.online.snapshots.at(-1).bullets.some(b=>b.owner===id&&b.kind==="grenade")', $ids->[1]), 'P1 detonation does not detonate local P2 grenade');
        }
    }
    main::fixture($code, undef, 'win', $ids->[0]);
    wait_js($host, '__test.phase==="roundOver"');
    evaluate_js($host, '__fireFrames=[];__fireRecord=true');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(1500));
    evaluate_js($host, '__fireRecord=false');
    $f = evaluate_js($host, '__fireFrames');
    $labels = unique_values([map { my $v = $_; $v->{'label'} } @{$f}]);
    $fills = unique_values([map { my $v = $_; $v->{'fill'} } @{$f}]);
    main::check((do { my $boolean_value = (value_eq($labels, ['DONE'])); truth_value($boolean_value) ? (value_eq(scalar(@{$fills}), 1)) : $boolean_value }), 'Winning cooldown and Fire label remain completely stable across real snapshots');
    wait_js($host, '__test.phase==="matchOver"');
    wait_js($viewer, '__test.phase==="matchOver"');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(200));
    main::check((value_eq($host->locator('#cooldownText1')->innerText(), 'MATCH COMPLETE')), 'Completed-match HUD does not advertise a live cooldown');
    $host->screenshot({path => format_value($out->child('winner-desktop.png'))});
    $viewer->screenshot({path => format_value($out->child('winner-viewer-390.png'))});
    $old = evaluate_js($host, '__test.online.id');
    evaluate_js($host, '__test.online.socket.close(4000,"test resume")');
    wait_js($host, '!__test.online.connected');
    wait_js($host, '__test.online.connected', undef, {timeout => 15000});
    main::check((value_eq(evaluate_js($host, '__test.online.id'), $old)), 'Reconnect retains primary identity');
    main::check((value_eq(evaluate_js($host, '__test.online.shots.previews.size'), 0)), 'Reconnect has no stale speculative projectiles');
    main::check((!truth_value($errors)), ('No JavaScript errors: ' . format_value($errors)));
1;
};
my $caught_error = $@;
for $c (@{$contexts}) {
    $c->close();
}
$b->close();
$out->child('results.json')->spew_utf8(json_text({'version' => '4.2.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors}, 1));
$out->child('frames.json')->spew_utf8(json_text($measurements));
die $caught_error if $caught_error;
print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
