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

my ($args, $assets, $b, $checks, $code, $ctx, $errors, $guest, $host, $html, $i, $js, $me, $old, $out, $p, $pa, $pw, $root, $state, $viewer, $web);
# v3.8 Scope integration through real local Go WebSockets and exact browser assets.
# Uses the opt-in _test.go fixture for deterministic grants only. No production cheats.
$pa = {};
$args = do { my %args = ('url' => undef, 'output' => 'test-output/scope38-online'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl scope38_online_browser.pl url --output
'; if ($help) { print 'Usage: perl scope38_online_browser.pl url --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
sub check {
    my ($ok, $s) = @_;
    assert_ok($ok, $s);
    push(@{$checks}, $s);
    print(join(" ", 'PASS', $s), "\n");
}
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script src="[^"]+" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . ('})(new URL(' . json_text(($args->{'url'} . '/?test=1')) . '));')) . substr($js, ($i + 4)));
sub load {
    my ($c) = @_;
    my ($p);
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->setContent($html);
    evaluate_js($p, '()=>{const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.muted\':\'1\'})});Object.defineProperty(window,\'sessionStorage\',{value:store({})});}');
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    $p->locator('#joinOtherBtn')->click();
    return $p;
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
eval {
    $ctx = $b->newContext({viewport => {'width' => 1365, 'height' => 950}});
    $host = main::load($ctx);
    $host->locator('#pilotName')->fill('SCOPE HOST');
    $host->locator('#createRoomBtn')->click();
    wait_js($host, 'leqra.getState().online?.connected');
    $code = evaluate_js($host, 'leqra.getState().online.code');
    $host->locator('#addLocalBtn')->click();
    wait_js($host, 'leqra.getState().room.players.length===2');
    $host->locator('[data-room-mode="koth"]')->click();
    wait_js($host, 'leqra.getState().rules.mode===\'koth\'');
    $host->locator('#roomMapSize')->selectOption('giant');
    wait_js($host, '(value)=>leqra.getState().rules.mapSize===value', 'giant', {});
    $host->locator('#roomRulesBtn')->click();
    $host->locator('#rule-timeLimit')->fill('600');
    $host->locator('#rule-scoreTarget')->fill('300');
    $host->locator('#rule-pickupRate')->selectOption('off');
    $host->locator('#applyRulesBtn')->click();
    wait_js($host, 'leqra.getState().rules.mapSize==="giant"');
    $guest = main::load($ctx);
    $guest->locator('#pilotName')->fill('GUEST');
    $guest->locator('#joinCode')->fill($code);
    $guest->locator('#joinRoomBtn')->click();
    wait_js($guest, 'leqra.getState().online?.connected');
    $guest->locator('#readyBtn')->click();
    $viewer = main::load($ctx);
    $viewer->locator('#pilotName')->fill('WATCHER');
    $viewer->locator('#joinCode')->fill($code);
    $viewer->locator('#joinRoomBtn')->click();
    wait_js($viewer, 'leqra.getState().online?.connected');
    evaluate_js($viewer, '()=>{const s=leqra.getState();__test.setPlayerSpectating(s.room.players.find(p=>p.id===s.online.id),true);}');
    wait_js($viewer, 'leqra.getState().online.spectating');
    if (truth_value((!value_eq($guest->locator('#readyBtn')->getAttribute('aria-pressed'), 'true')))) {
        $state = evaluate_js($guest, 'leqra.getState()');
        $me = ([map { my $p = $_; truth_value((value_eq($p->{'id'}, $state->{'online'}->{'id'}))) ? ($p) : () } @{$state->{'room'}->{'players'}}]->[0] // undef);
        if (truth_value((!truth_value(($me->{'ready'} // undef))))) {
            $guest->locator('#readyBtn')->click();
        }
    }
    wait_js($host, '!document.querySelector("#startRoomBtn").disabled');
    $host->locator('#startRoomBtn')->click();
    for $p (@{[$host, $guest, $viewer]}) {
        wait_js($p, 'leqra.getState().phase==="playing"');
    }
    main::check(!scalar(grep { my $p = $_; !(evaluate_js($p, 'leqra.getState().world.cols===16 && leqra.getState().world.rows===14')) } @{[$host, $guest, $viewer]}), 'All live clients render authoritative 16x14 world');
    sub grant {
        my ($expire) = @_;
        my ($r, $req);
        $expire //= JSON::PP::false;
        $req = HTTP::Request->new('POST', ($args->{'url'} . '/_fixture/scope38'), [%{{'Content-Type' => 'application/json'}}], Encode::encode_utf8(json_text({'code' => $code, 'expire' => $expire})));
        $r = request_ok($req);
        assert_ok((value_eq($r->code, 204)), 'r.status==204');
    }
    main::grant();
    for $p (@{[$host, $guest, $viewer]}) {
        wait_js($p, 'leqra.getState().tanks.every(t=>t.scopeTime>7)');
    }
    main::check(JSON::PP::true, 'Scope grant and timer delivered to players and spectator through snapshots');
    wait_js($host, 'document.querySelector(\'#buffLabel\').textContent.includes(\'SCP\') && document.querySelector(\'#buffLabel2\').textContent.includes(\'SCP\')');
    main::check((do { my $boolean_value = (contains_value($host->locator('#buffLabel')->innerText(), 'SCP')); truth_value($boolean_value) ? (contains_value($host->locator('#buffLabel2')->innerText(), 'SCP')) : $boolean_value }), 'Online primary and secondary HUDs both show Scope timers');
    sub guides {
        my ($p) = @_;
        return evaluate_js($p, '()=>{const T=__test,c=document.querySelector(\'#arena\').getContext(\'2d\'),old=c.moveTo;let count=0;c.moveTo=function(...args){count++;return old.apply(this,args)};try{T.drawAimingGuides();return count;}finally{c.moveTo=old;}}');
    }
    main::check((value_eq(main::guides($host), 2)), 'Online host draws two owned Scope guides');
    main::check((value_eq(main::guides($guest), 1)), 'Guest draws only their own guide, not opponents\' scopes');
    main::check((value_eq(main::guides($viewer), 0)), 'Spectator has no controllable tank and no personal guide');
    main::check(evaluate_js($viewer, 'leqra.getState().online.spectating'), 'Grant never turns spectator into a player');
    $old = evaluate_js($host, 'leqra.getState().online.id');
    evaluate_js($host, '__test.online.socket.close(4000,"scope reconnect test")');
    wait_js($host, '!leqra.getState().online.connected');
    wait_js($host, 'leqra.getState().online.connected', undef, {timeout => 12000});
    wait_js($host, 'leqra.getState().tanks.some(t=>t.scopeTime>0)');
    main::check((do { my $boolean_value = (value_eq(evaluate_js($host, 'leqra.getState().online.id'), $old)); truth_value($boolean_value) ? ((evaluate_js($host, 'leqra.getState().tanks[0].scopeTime') > 0)) : $boolean_value }), 'Reconnection preserves ownership and an active Scope buff');
    $host->screenshot({path => format_value($out->child('online-scopes.png'))});
    main::grant(JSON::PP::true);
    for $p (@{[$host, $guest, $viewer]}) {
        wait_js($p, 'leqra.getState().tanks.every(t=>t.scopeTime===0)');
    }
    wait_js($host, '!document.querySelector(\'#buffLabel\').textContent.includes(\'SCP\') && !document.querySelector(\'#buffLabel2\').textContent.includes(\'SCP\')');
    main::check((do { my $boolean_value = (!(contains_value($host->locator('#buffLabel')->innerText(), 'SCP'))); truth_value($boolean_value) ? (!(contains_value($host->locator('#buffLabel2')->innerText(), 'SCP'))) : $boolean_value }), 'Authoritative expiry clears both online Scope HUD indicators');
    main::check((value_eq(main::guides($host), 1)), 'Expiry restores original primary-only short aiming guide');
    main::check((!truth_value($errors)), 'No uncaught live browser errors');
    $out->child('results.json')->spew_utf8(json_text({'version' => '3.8.0', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Real loopback Go sockets; injected assets/URL/storage; _test.go grant endpoint only; no physical devices.'}, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
$b->close();
die $caught_error if $caught_error;
