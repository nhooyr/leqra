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

my ($a, $args, $assets, $b, $base, $before, $browser, $code, $context, $contexts, $current, $errors, $host, $html, $i, $jitter, $js, $k, $key, $n, $observer, $old, $options, $out, $page, $pages, $parser, $pos, $profiles, $pw, $report, $request, $response, $roles, $root, $seq, $state1, $state2, $traces, $watching, $wrapper);
# Live two-browser smoothing test with ordered synthetic WebSocket delay.
# 
# Uses real sockets to a dedicated test server. Delays are injected only by this
# harness (not shipped game code). No real packet loss or public WAN is simulated.
# Requires optional Playwright; see TESTING.md for the opt-in isolated fixture.
$parser = {};
$args = do { my %args = ('url' => 'http://localhost:8080', 'assets' => format_value(path($0)->absolute->parent(2)->child('web')), 'isolated' => undef, 'browser' => undef, 'output' => 'test-output/network', 'motion' => 'turn', 'profile' => 'jitter', 'local2' => undef, 'roles' => undef, 'legacy' => undef); my $help; GetOptions('assets=s' => \$args{'assets'}, 'isolated!' => \$args{'isolated'}, 'browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'motion=s' => \$args{'motion'}, 'profile=s' => \$args{'profile'}, 'local2!' => \$args{'local2'}, 'roles!' => \$args{'roles'}, 'legacy!' => \$args{'legacy'}, 'help|h' => \$help) or die 'Usage: perl network_smoothing.pl url --assets --isolated --browser --output --motion --profile --local2 --roles --legacy
'; if ($help) { print 'Usage: perl network_smoothing.pl url --assets --isolated --browser --output --motion --profile --local2 --roles --legacy
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; die 'invalid motion
' if defined($args{'motion'}) && !grep { value_eq($_, $args{'motion'}) } @{['turn', 'move']}; die 'invalid profile
' if defined($args{'profile'}) && !grep { value_eq($_, $args{'profile'}) } @{['lan', 'jitter', 'heavy']}; \%args; };
$root = path($args->{'assets'});
$assets = asset_directory($root);
$out = path($args->{'output'});
$out->mkpath;
$html = $root->child('index.html')->slurp_utf8;
$html = replace_re('<link[^>]*>', '', $html);
$html = replace_re('<script src="(?:game|netcode)\\.js" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
$pos = rindex($js, '})()');
$js = ((substr($js, 0, $pos - 0) . ('})(new URL(' . json_text(($args->{'url'} . '/?test=1')) . '));')) . substr($js, ($pos + 4)));
$wrapper = ordered_delay_script();
$profiles = {'lan' => [0, [0]], 'jitter' => [60, [0, 45, 8, 27, 65, 2, 30, 12]], 'heavy' => [110, [0, 70, 15, 40, 100, 5, 65, 20]]};
my $tuple_67_0 = $profiles->{$args->{'profile'}};
$base = $tuple_67_0->[0];
$jitter = $tuple_67_0->[1];
$wrapper = replace_text($wrapper, 'base:60,jitter:[0,45,8,27,65,2,30,12]', ((('base:' . format_value($base)) . ',jitter:') . json_text($jitter)));
sub wrap_angle {
    my ($a, $b) = @_;
    return atan2(sin(($b - $a)), cos(($b - $a)));
}
sub metrics {
    my ($frames, $tank_id) = @_;
    my ($a, $b, $dt, $end, $f, $samples, $start, $t, $v, $velocity, $x);
    $samples = [];
    for $f (@{$frames}) {
        $t = ([map { my $x = $_; truth_value((value_eq($x->{'id'}, $tank_id))) ? ($x) : () } @{$f->{'tanks'}}]->[0] // undef);
        if (truth_value((do { my $boolean_value = $t; truth_value($boolean_value) ? do { my $boolean_value = $t->{'alive'}; truth_value($boolean_value) ? (value_eq($f->{'phase'}, 'playing')) : $boolean_value } : $boolean_value }))) {
            push(@{$samples}, [$f->{'at'}, (truth_value((value_eq($args->{'motion'}, 'turn'))) ? $t->{'angle'} : $t->{'x'})]);
        }
    }
    if (truth_value((!truth_value($samples)))) {
        return {};
    }
    my $tuple_77_1 = [($samples->[0]->[0] + 1200), ($samples->[(-1)]->[0] - 300)];
    $start = $tuple_77_1->[0];
    $end = $tuple_77_1->[1];
    $velocity = [];
    for my $item (@{[map { my $i = $_; [$samples->[$i], array_slice($samples, 1, undef)->[$i]] } 0 .. min($#{$samples}, $#{array_slice($samples, 1, undef)})]}) {
        my $tuple_79_5 = $item;
        my $a = $tuple_79_5->[0];
        my $b = $tuple_79_5->[1];
        my $dt = (($b->[0] - $a->[0]) / 1000);
        if (truth_value((do { my $boolean_value = (($a->[0] < $start)); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($b->[0] > $end)); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($dt <= 0)); truth_value($boolean_value) ? $boolean_value : (($dt > 0.05)) } } }))) {
            next;
        }
        push(@{$velocity}, ((truth_value((value_eq($args->{'motion'}, 'turn'))) ? main::wrap_angle($a->[1], $b->[1]) : ($b->[1] - $a->[1])) / $dt));
    }
    return {'frames' => scalar(@{$velocity}), 'units' => (truth_value((value_eq($args->{'motion'}, 'turn'))) ? 'radians/second' : 'world units/second'), 'mean_speed' => mean($velocity), 'speed_stddev' => stddev($velocity), 'backward_frames' => sum(@{[map { my $v = $_; (($v < (-0.05))) } @{$velocity}]}), 'near_stopped_frames' => sum(@{[map { my $v = $_; ((abs($v) < 0.1)) } @{$velocity}]}), 'max_speed' => max(@{$velocity}), 'min_speed' => min(@{$velocity})};
}
$pw = start_playwright();
my $playwright = $pw;
$options = {'headless' => JSON::PP::true};
if (truth_value($args->{'browser'})) {
    $options->{'executablePath'} = $args->{'browser'};
}
$browser = $pw->launch(type => 'chrome', %{$options});
$errors = [];
$pages = [];
$contexts = [];
for $i (@{[0 .. 2 - 1]}) {
    $context = $browser->newContext({viewport => {'width' => (truth_value((value_eq($i, 0))) ? 1365 : 390), 'height' => (truth_value((value_eq($i, 0))) ? 950 : 844)}, isMobile => (value_eq($i, 1)), hasTouch => (value_eq($i, 1))});
    push(@{$contexts}, $context);
    $page = $context->newPage();
    $page->setDefaultTimeout(10000);
    push(@{$pages}, $page);
    capture_event($page, 'pageerror', $errors, '(e) => String(e)');
    if (truth_value($args->{'isolated'})) {
        $page->setContent($html);
        evaluate_js($page, $wrapper);
        if (truth_value($assets->child('netcode.js')->exists)) {
            $page->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
        }
        $page->addScriptTag({content => $js});
    } else {
        $page->addInitScript($wrapper);
        $page->goto(($args->{'url'} . '/?test=1'));
    }
    wait_js($page, 'window.leqra');
    $page->locator((truth_value($args->{'legacy'}) ? '[data-mode=online]' : '#joinOtherBtn'))->click();
    $page->locator('#pilotName')->fill((truth_value((value_eq($i, 0))) ? 'SMOOTH' : 'OBSERVER'));
}
print(join(" ", 'Clients loaded'), "\n");
my $tuple_104_1 = $pages;
$host = $tuple_104_1->[0];
$observer = $tuple_104_1->[1];
$host->locator('#createRoomBtn')->click();
wait_js($host, 'leqra.getState().online?.connected');
$code = evaluate_js($host, 'leqra.getState().online.code');
$observer->locator('#joinCode')->fill($code);
$observer->locator('#joinRoomBtn')->click();
wait_js($observer, 'leqra.getState().online?.connected');
print(join(" ", 'Clients joined'), "\n");
for $page (@{$pages}) {
    wait_js($page, 'leqra.getState().online.players.length===2');
}
if (truth_value($args->{'local2'})) {
    $host->locator('#addLocalBtn')->click();
    for $page (@{$pages}) {
        wait_js($page, 'leqra.getState().online.players.length===3');
    }
}
if (truth_value($args->{'roles'})) {
    assert_ok($args->{'local2'}, '--roles requires --local2');
    $host->locator('#roomTeamMode')->selectOption('teams');
    wait_js($host, '(value)=>leqra.getState().rules.teamMode===value', 'teams', {});
    $host->locator('#roomRulesBtn')->click();
    $host->locator('#applyRulesBtn')->click();
    wait_js($host, 'leqra.getState().rules.teamMode==="teams"');
    $host->locator('#roomRoster [data-team="2"]')->selectOption('3');
    wait_js($host, 'leqra.getState().room.players.some(p=>p.id===2&&p.team===3)');
}
for $page (@{$pages}) {
    if (truth_value($page->locator('#readyBtn')->isVisible())) {
        $page->locator('#readyBtn')->click();
    }
}
wait_js($host, '!document.querySelector("#startRoomBtn").disabled');
$host->locator('#startRoomBtn')->click();
for $page (@{$pages}) {
    wait_js($page, 'leqra.getState().phase==="playing"');
}
print(join(" ", 'Match running'), "\n");
if (truth_value((value_eq($args->{'motion'}, 'move')))) {
    print(join(" ", 'Installing lane fixture'), "\n");
    $request = HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/lane'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code})));
    $response = request_ok($request);
    assert_ok((value_eq($response->code, 200)), 'response.status==200');
    print(join(" ", 'Lane HTTP response received'), "\n");
    for $page (@{$pages}) {
        wait_js($page, 'leqra.getState().world.cols===20', undef, {timeout => 10000});
    }
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(500));
}
print(join(" ", 'Recording motion'), "\n");
for $page (@{$pages}) {
    evaluate_js($page, '__frames=[];__record=true');
}
$key = (truth_value((value_eq($args->{'motion'}, 'turn'))) ? 'KeyD' : 'KeyW');
evaluate_js($host, 'key=>window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:key,bubbles:true}))', $key);
if (truth_value($args->{'local2'})) {
    evaluate_js($host, 'key=>window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:key,bubbles:true}))', (truth_value((value_eq($args->{'motion'}, 'turn'))) ? 'ArrowRight' : 'ArrowUp'));
}
$Leqra::Browser::HANDLE->await($host->waitForTimeout(7400));
for $page (@{$pages}) {
    evaluate_js($page, '__record=false');
}
evaluate_js($host, 'key=>window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:key,bubbles:true}))', $key);
if (truth_value($args->{'local2'})) {
    evaluate_js($host, 'key=>window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:key,bubbles:true}))', (truth_value((value_eq($args->{'motion'}, 'turn'))) ? 'ArrowRight' : 'ArrowUp'));
}
$traces = [map { my $page = $_; evaluate_js($page, '__frames') } @{$pages}];
$report = {'local' => main::metrics($traces->[0], 0), 'remote' => main::metrics($traces->[1], 0), 'profile' => $args->{'profile'}, 'motion' => $args->{'motion'}, 'injected_one_way_base_ms' => $base, 'ordered_per_message_jitter_ms' => $jitter, 'latency_ms' => [map { my $page = $_; evaluate_js($page, 'leqra.getState().online.latency') } @{$pages}], 'smoothing' => [map { my $page = $_; evaluate_js($page, 'leqra.getState().online.smoothing||null') } @{$pages}], 'browser' => $browser->version(), 'errors' => $errors, 'isolated' => $args->{'isolated'}};
if (truth_value($args->{'local2'})) {
    $report->{'secondary_local'} = main::metrics($traces->[0], 2);
    $report->{'secondary_remote'} = main::metrics($traces->[1], 2);
    assert_ok((do { my $boolean_value = (($report->{'secondary_local'}->{'frames'} > 100)); truth_value($boolean_value) ? (value_eq($report->{'secondary_local'}->{'backward_frames'}, 0)) : $boolean_value }), $report);
    assert_ok((do { my $boolean_value = (($report->{'secondary_remote'}->{'frames'} > 100)); truth_value($boolean_value) ? (($report->{'secondary_remote'}->{'near_stopped_frames'} <= 2)) : $boolean_value }), $report);
}
assert_ok((!truth_value($errors)), $errors);
assert_ok((do { my $boolean_value = (($report->{'local'}->{'frames'} > 100)); truth_value($boolean_value) ? (($report->{'remote'}->{'frames'} > 100)) : $boolean_value }), $report);
if (truth_value((!truth_value($args->{'legacy'})))) {
    assert_ok((value_eq($report->{'local'}->{'backward_frames'}, 0)), $report);
    assert_ok((value_eq($report->{'remote'}->{'backward_frames'}, 0)), $report);
    assert_ok((($report->{'remote'}->{'near_stopped_frames'} <= 2)), $report);
    assert_ok((($report->{'remote'}->{'speed_stddev'} < (truth_value((value_eq($args->{'motion'}, 'turn'))) ? 0.65 : 20))), $report);
}
if (truth_value($args->{'roles'})) {
    for $k (@{['KeyD', 'ArrowRight']}) {
        evaluate_js($host, 'k=>window.dispatchEvent(new KeyboardEvent(\'keydown\',{code:k,bubbles:true}))', $k);
    }
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(900));
    $roles = [];
    for $watching (@{[JSON::PP::true, JSON::PP::false, JSON::PP::true]}) {
        $before = evaluate_js($host, '({primary:__test.online.seq,secondary:__test.online.secondary.seq})');
        evaluate_js($observer, 'v=>{const s=leqra.getState();__test.setPlayerSpectating([...s.room.players,...s.room.spectators].find(p=>p.id===s.online.id),v)}', $watching);
        wait_js($observer, 'v=>leqra.getState().online.spectating===v', $watching, {});
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(450));
        $seq = evaluate_js($host, '({primary:__test.online.seq,secondary:__test.online.secondary.seq})');
        assert_ok((do { my $boolean_value = (($seq->{'primary'} >= $before->{'primary'})); truth_value($boolean_value) ? (($seq->{'secondary'} >= $before->{'secondary'})) : $boolean_value }), [$before, $seq]);
        $state1 = evaluate_js($host, '__test.online.snapshots.at(-1).tanks.filter(t=>[0,2].includes(t.id)).map(t=>({id:t.id,angle:t.angle,ack:t.ack}))');
        $Leqra::Browser::HANDLE->await($host->waitForTimeout(600));
        $state2 = evaluate_js($host, '__test.online.snapshots.at(-1).tanks.filter(t=>[0,2].includes(t.id)).map(t=>({id:t.id,angle:t.angle,ack:t.ack}))');
        for my $item (@{[map { my $i = $_; [$state1->[$i], $state2->[$i]] } 0 .. min($#{$state1}, $#{$state2})]}) {
            my $tuple_175_7 = $item;
            my $a = $tuple_175_7->[0];
            my $b = $tuple_175_7->[1];
            assert_ok((do { my $boolean_value = (value_eq($a->{'id'}, $b->{'id'})); truth_value($boolean_value) ? do { my $boolean_value = (($b->{'ack'} > $a->{'ack'})); truth_value($boolean_value) ? ((abs(main::wrap_angle($a->{'angle'}, $b->{'angle'})) > 0.5)) : $boolean_value } : $boolean_value }), [$a, $b]);
        }
        push(@{$roles}, {'spectating' => $watching, 'sequences_before' => $before, 'sequences_after' => $seq, 'server_before' => $state1, 'server_after' => $state2});
    }
    $report->{'spectator_role_changes_under_delay'} = $roles;
    for $k (@{['KeyD', 'ArrowRight']}) {
        evaluate_js($host, 'k=>window.dispatchEvent(new KeyboardEvent(\'keyup\',{code:k,bubbles:true}))', $k);
    }
}
print(join(" ", 'Testing resume'), "\n");
$old = evaluate_js($host, 'leqra.getState().online');
$n = evaluate_js($host, '__sockets.length');
evaluate_js($host, '__sockets.at(-1).close(4000,"Delayed-network reconnection test")');
wait_js($host, 'n=>__sockets.length>n&&leqra.getState().online?.connected', $n, {timeout => 12000});
$current = evaluate_js($host, 'leqra.getState().online');
assert_ok((do { my $boolean_value = (value_eq($current->{'id'}, $old->{'id'})); truth_value($boolean_value) ? (value_eq($current->{'code'}, $old->{'code'})) : $boolean_value }), 'current[\'id\']==old[\'id\'] and current[\'code\']==old[\'code\']');
$report->{'reconnected_under_delay'} = JSON::PP::true;
$Leqra::Browser::HANDLE->await($host->waitForTimeout(700));
for my $item (@{[map { [$_, $pages->[$_]] } 0 .. $#{$pages}]}) {
    my $tuple_189_5 = $item;
    my $i = $tuple_189_5->[0];
    my $page = $tuple_189_5->[1];
    $page->screenshot({path => format_value($out->child(('jitter-' . $i . '.png')))});
}
$out->child('frames.json')->spew_utf8(json_text($traces));
$out->child('results.json')->spew_utf8(json_text($report, 1));
print(join(" ", json_text($report, 1)), "\n");
$browser->close();
