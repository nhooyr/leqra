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
use Leqra::Protocol ();

my ($after_notify, $ap, $args, $assets, $b, $battle, $before_notify, $before_opp, $c, $chat_text, $checks, $errors, $fc, $friend, $fs, $h, $hc, $home, $host, $hs, $html, $i, $js, $key, $m, $observer, $old, $opp, $out, $own, $p, $peers, $pw, $q, $r, $report, $root, $roster, $sc, $solo, $state, $w, $watch, $wc, $web);
# v4.0 queue UI + real Go sockets. Browser assets are injected because the
# sandbox blocks navigation; only Location/History/storage have test adapters.
# Use TestBrowserFixture for opaque about:blank origins, never a production bypass.
$ap = {};
$args = do { my %args = ('url' => 'http://127.0.0.1:18041', 'output' => 'test-output/matchmaking40'); my $help; GetOptions('output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl matchmaking_browser.pl url --output
'; if ($help) { print 'Usage: perl matchmaking_browser.pl url --output
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
$checks = [];
$errors = [];
$peers = [];
sub new_peer {
    my $peer = Leqra::Protocol::peer($args->{url}, action_interval => 0, timeout => 10);
    push @$peers, $peer;
    return $peer;
}
sub leave_peer {
    my ($peer) = @_;
    eval { $peer->send({type => 'leave'}); Leqra::Protocol::pause(0.04); $peer->close; };
}
sub check {
    my ($ok, $text) = @_;
    assert_ok($ok, $text);
    push(@{$checks}, $text);
    print(join(" ", 'PASS', $text), "\n");
}
$html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
$html = replace_re('<script src="[^"]+" defer></script>', '', $html);
$html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
$js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1);
$i = rindex($js, '})()');
$js = ((substr($js, 0, $i - 0) . '})(window.__location,window.__history);') . substr($js, ($i + 4)));
sub load {
    my ($b, $name, $w, $h, $invite) = @_;
    my ($c, $mobile, $p);
    $w //= 1365;
    $h //= 950;
    $invite //= '';
    $mobile = (do { my $boolean_value = (($w < 760)); truth_value($boolean_value) ? $boolean_value : (($h < 620)) });
    $c = $b->newContext({viewport => {'width' => $w, 'height' => $h}, hasTouch => $mobile, isMobile => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
    $p = $c->newPage();
    capture_event($p, 'pageerror', $errors, '(e) => String(e)');
    $p->on('dialog', 'arguments[0].accept();');
    $p->setContent($html);
    evaluate_js($p, 'a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(state,title,url){this.state=state;window.__updatedURL=String(url);}};
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.muted\':\'1\',\'leqra.name\':a.name})});Object.defineProperty(window,\'sessionStorage\',{value:store({})});}', {'url' => (($args->{'url'} . '/?test=1') . $invite), 'name' => $name});
    $p->addScriptTag({content => $assets->child('theme.js')->slurp_utf8});
    $p->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
    $p->addScriptTag({content => $js});
    wait_js($p, 'window.leqra');
    return [$p, $c];
}
sub queue_party_wire {
    my ($n, $key) = @_;
    my ($unused, $code, $i, $p, $people, $qid, $r, $w);
    $people = [map { my $unused = $_; new_peer() } @{[0 .. $n - 1]}];
    $w = $people->[0]->op('create', sub { my ($m) = @_; return (value_eq($m->{'type'}, 'welcome')); }, 'name' => 'Opponent 1');
    $code = $w->{'room'};
    for my $item (@{[map { [$_, array_slice($people, 1, undef)->[$_]] } 0 .. $#{array_slice($people, 1, undef)}]}) {
        my $tuple_53_8 = $item;
        my $i = $tuple_53_8->[0];
        my $p = $tuple_53_8->[1];
        $p->op('join', sub { my ($m) = @_; return (value_eq($m->{'type'}, 'welcome')); }, 'code' => $code, 'name' => ('Opponent ' . format_value(($i + 2))));
    }
    $r = $people->[0]->op('queue_join', sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'room')); truth_value($boolean_value) ? ($m->{'queue'} // undef) : $boolean_value }); }, 'queue' => $key);
    $qid = $r->{'queue'}->{'id'};
    for $p (@{array_slice($people, 1, undef)}) {
        $p->op('queue_accept', sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'room')); truth_value($boolean_value) ? ($m->{'queue'} // undef) : $boolean_value }); }, 'queueId' => $qid, 'ready' => JSON::PP::true);
    }
    return $people;
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => '/usr/bin/chromium');
eval {
    for my $item (@{[[1365, 950], [390, 844], [320, 568], [844, 390]]}) {
        my $tuple_63_12 = $item;
        my $w = $tuple_63_12->[0];
        my $h = $tuple_63_12->[1];
        my $tuple_64_12 = main::load($b, 'Menu Test', $w, $h);
        my $p = $tuple_64_12->[0];
        my $c = $tuple_64_12->[1];
        $p->locator('#matchmakingBtn')->click();
        main::check((do { my $boolean_value = evaluate_js($p->locator('#queueDialog'), '(e)=>e.open'); truth_value($boolean_value) ? (value_eq($p->locator('[data-queue]')->count(), 6)) : $boolean_value }), ($w . 'x' . $h . ': six real queue cards open'));
        for my $key (@{['elimination-1', 'elimination-2', 'elimination-3', 'ctf-3', 'koth-3', 'ffa-8']}) {
            $p->locator((('[data-queue="' . $key) . '"]'))->click();
            main::check((value_eq($p->locator((('[data-queue="' . $key) . '"]'))->getAttribute('aria-pressed'), 'true')), ($w . 'x' . $h . ': select ' . $key));
        }
        main::check(evaluate_js($p, 'document.body.scrollWidth<=innerWidth+1'), ($w . 'x' . $h . ': no horizontal overflow'));
        $p->locator('[data-queue="ctf-3"]')->click();
        $p->screenshot({path => format_value($out->child(('queues-' . $w . 'x' . $h . '.png')))});
        $p->locator('#queueCloseBtn')->click();
        $c->close();
    }
    my $tuple_75_8 = main::load($b, 'SOLO TEST');
    $solo = $tuple_75_8->[0];
    $sc = $tuple_75_8->[1];
    $solo->locator('#matchmakingBtn')->click();
    $solo->locator('#queueStartBtn')->click();
    wait_js($solo, 'leqra.getState().room?.queue?.stage==="searching"');
    $state = evaluate_js($solo, 'leqra.getState()');
    $home = $state->{'online'}->{'code'};
    main::check((do { my $boolean_value = (value_eq($state->{'room'}->{'queue'}->{'players'}, 1)); truth_value($boolean_value) ? (value_eq(scalar(@{$state->{'room'}->{'players'}}), 4)) : $boolean_value }), 'One real pilot queues; three default bots remain private');
    main::check((value_eq(query_values(URI->new(evaluate_js($solo, 'window.__updatedURL'))->query)->{'room'}, [$home])), 'Publishing for queue updates the invite URL adapter');
    $solo->locator('#queueCloseBtn')->click();
    main::check(evaluate_js($solo, '!!leqra.getState().room.queue'), 'Closing chooser does not cancel queue');
    $solo->locator('#matchmakingBtn')->click();
    $solo->locator('#queueCancelBtn')->click();
    wait_js($solo, '!leqra.getState().room.queue');
    main::check((value_eq(evaluate_js($solo, 'leqra.getState().online.code'), $home)), 'Cancel retains same online party and lobby');
    $solo->locator('#queueCloseBtn')->click();
    evaluate_js($solo, '__test.online.socket.send(JSON.stringify({type:"leave"}))');
    $sc->close();
    my $tuple_92_8 = main::load($b, 'Party Host');
    $host = $tuple_92_8->[0];
    $hc = $tuple_92_8->[1];
    $host->locator('#addLocalBtn')->click();
    $host->locator('#roomP2Callsign')->fill('Keyboard Ally');
    $host->locator('#roomP2Callsign')->press('Enter');
    $host->locator('#copyInviteBtn')->click();
    wait_js($host, 'leqra.getState().online?.connected');
    $home = evaluate_js($host, 'leqra.getState().online.code');
    my $tuple_99_8 = main::load($b, 'Remote Ally', 320, 568, ('&room=' . $home));
    $friend = $tuple_99_8->[0];
    $fc = $tuple_99_8->[1];
    wait_js($friend, 'leqra.getState().online?.connected');
    wait_js($host, 'leqra.getState().room.players.length===6');
    main::check((do { my $boolean_value = $host->locator('#roomCodeEditor')->isVisible(); truth_value($boolean_value) ? $friend->locator('#roomCodeEditor')->isHidden() : $boolean_value }), 'Only the host can edit the online room code');
    $host->locator('#onlineRoomCode')->fill('Party Room 420');
    $host->locator('#onlineRoomCode')->press('Enter');
    wait_js($host, 'leqra.getState().online.code==="Party Room 420"');
    wait_js($friend, 'leqra.getState().online.code==="Party Room 420"');
    $home = 'Party Room 420';
    main::check((do { my $boolean_value = (value_eq(query_values(URI->new(evaluate_js($host, 'window.__updatedURL'))->query)->{'room'}, [$home])); truth_value($boolean_value) ? (value_eq(query_values(URI->new(evaluate_js($friend, 'window.__updatedURL'))->query)->{'room'}, [$home])) : $boolean_value }), 'Room rename updates every connected member and invite URL');
    $observer = new_peer();
    $observer->op('join', sub { my ($m) = @_; return (value_eq($m->{'type'}, 'welcome')); }, 'code' => $home, 'name' => 'Home Viewer', 'spectating' => JSON::PP::true);
    $host->locator('#matchmakingBtn')->click();
    $host->locator('[data-queue="elimination-1"]')->click();
    main::check($host->locator('#queueStartBtn')->isDisabled(), 'Three-person party cannot enter 1v1');
    $host->locator('[data-queue="ffa-8"]')->click();
    main::check((do { my $boolean_value = $host->locator('#queueStartBtn')->isDisabled(); truth_value($boolean_value) ? (contains_value($host->locator('#queueNotice')->innerText(), 'solo-entry')) : $boolean_value }), 'Free-for-all rejects allied party entry');
    $host->locator('[data-queue="ctf-3"]')->click();
    $host->locator('#queueStartBtn')->click();
    wait_js($host, 'leqra.getState().room?.queue?.stage==="confirming"');
    wait_js($friend, 'document.querySelector("#queueDialog").open');
    main::check($friend->locator('#queueAcceptBtn')->isVisible(), 'Remote friend must explicitly confirm selected queue');
    $q = evaluate_js($host, 'leqra.getState().room.queue');
    main::check((do { my $boolean_value = (value_eq($q->{'players'}, 3)); truth_value($boolean_value) ? (value_eq(sum(@{[map { my $p = $_; $p->{'accepted'} } @{$q->{'members'}}]}), 2)) : $boolean_value }), 'Local P2 counts as a real player; host confirms both keyboard pilots');
    main::check($friend->locator('#queueStartBtn')->isHidden(), 'Guest cannot choose or start a different queue');
    $friend->screenshot({path => format_value($out->child('party-confirm-320.png'))});
    $friend->locator('#queueAcceptBtn')->click();
    wait_js($host, 'leqra.getState().room.queue?.stage==="searching"');
    wait_js($friend, 'leqra.getState().room.queue?.stage==="searching"');
    main::check(JSON::PP::true, 'Search activates only after friend consent');
    $host->screenshot({path => format_value($out->child('party-searching.png'))});
    $friend->locator('#queueCloseBtn')->click();
    $friend->locator('#chatBtn')->click();
    $friend->locator('#chatInput')->fill('Ready together');
    $friend->locator('#chatSendBtn')->click();
    $friend->locator('#chatCloseBtn')->click();
    $observer->wait(sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'chat')); truth_value($boolean_value) ? (value_eq($m->{'message'}->{'text'}, 'Ready together')) : $boolean_value }); });
    main::check(JSON::PP::true, 'Room chat still reaches a private spectator during the search');
    $opp = main::queue_party_wire(3, 'ctf-3');
    wait_js($host, '!!leqra.getState().room?.matchmaking', undef, {timeout => 15000});
    wait_js($friend, '!!leqra.getState().room?.matchmaking');
    $hs = evaluate_js($host, 'leqra.getState()');
    $fs = evaluate_js($friend, 'leqra.getState()');
    $battle = $hs->{'online'}->{'code'};
    main::check((do { my $boolean_value = (!value_eq($battle, $home)); truth_value($boolean_value) ? (value_eq($battle, $fs->{'online'}->{'code'})) : $boolean_value }), 'Party moves together to a distinct server-created battle');
    $roster = $hs->{'room'}->{'players'};
    $own = [map { my $p = $_; truth_value((contains_value(['Party Host', 'Keyboard Ally', 'Remote Ally'], $p->{'name'}))) ? ($p) : () } @{$roster}];
    main::check((do { my $boolean_value = (value_eq(scalar(@{$own}), 3)); truth_value($boolean_value) ? (value_eq(scalar(@{unique_values([map { my $p = $_; $p->{'team'} } @{$own}])}), 1)) : $boolean_value }), 'All three party members share one team');
    main::check((do { my $boolean_value = (value_eq(scalar(@{$roster}), 6)); truth_value($boolean_value) ? !scalar(grep { my $p = $_; !((!value_eq($p->{'kind'}, 'bot'))) } @{$roster}) : $boolean_value }), 'Full 3v3 lineup contains six real tanks, no bots');
    main::check((do { my $boolean_value = (value_eq($hs->{'rules'}->{'mode'}, 'ctf')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($hs->{'rules'}->{'mapSize'}, 'huge')); truth_value($boolean_value) ? (value_eq($hs->{'room'}->{'host'}, (-1))) : $boolean_value } : $boolean_value }), 'CTF queue applies fixed 14x12 rules and no player-host');
    main::check((do { my $boolean_value = (!truth_value(evaluate_js($host->locator('#queueDialog'), '(e)=>e.open'))); truth_value($boolean_value) ? (!truth_value(evaluate_js($friend->locator('#queueDialog'), '(e)=>e.open'))) : $boolean_value }), 'Match transfer closes queue dialogs automatically');
    $observer->wait(sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'room')); truth_value($boolean_value) ? (value_eq(($m->{'awayMatch'} // undef), $battle)) : $boolean_value }); });
    main::check(JSON::PP::true, 'Unqueued spectator remains in original room with a watchable match reference');
    main::check((value_eq(query_values(URI->new(evaluate_js($host, 'window.__updatedURL'))->query)->{'room'}, [$battle])), 'Match transfer updates public invite URL adapter');
    wait_js($host, 'leqra.getState().phase==="playing"', undef, {timeout => 15000});
    wait_js($friend, 'leqra.getState().phase==="playing"', undef, {timeout => 15000});
    main::check((value_eq(evaluate_js($host, 'leqra.getState().world.cols'), 14)), 'Countdown automatically leads into the actual maze');
    main::check((do { my $boolean_value = (value_eq($host->locator('#enemyChatBtn')->count(), 0)); truth_value($boolean_value) ? $host->locator('#chatBtn')->isVisible() : $boolean_value }), 'Matchmaking uses one integrated chat button');
    main::check(evaluate_js($friend, 'document.body.scrollWidth<=innerWidth+1'), '320px matchmaking HUD with integrated chat has no horizontal overflow');
    $before_opp = scalar(@{$opp->[0]->{'messages'}});
    $host->locator('#chatBtn')->click();
    main::check((do { my $boolean_value = (value_eq($host->locator('#chatTitle')->innerText(), 'Match chat')); truth_value($boolean_value) ? (value_eq($host->locator('#chatConnection')->innerText(), 'PARTY + OPPONENT MESSAGES')) : $boolean_value }), 'Integrated matchmaking chat identifies both incoming sources');
    main::check((do { my $boolean_value = $host->locator('#chatTargetSwitch')->isVisible(); truth_value($boolean_value) ? (!truth_value($host->locator('#chatOpponentToggle')->isChecked())) : $boolean_value }), 'Outgoing chat defaults to the party with a compact opponent toggle');
    $host->locator('#chatInput')->fill('Party secret');
    $host->locator('#chatSendBtn')->click();
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(100));
    $host->locator('#chatCloseBtn')->click();
    $friend->locator('#chatBtn')->click();
    wait_js($friend, 'document.querySelector("#chatMessages").textContent.includes("Party secret")');
    main::check(JSON::PP::true, 'Party-targeted matchmaking chat reaches the sender party');
    $friend->locator('#chatCloseBtn')->click();
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(100));
    main::check((!truth_value(scalar(grep { my $m = $_; (do { my $boolean_value = (value_eq(($m->{'type'} // undef), 'chat')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq(($m->{'channel'} // 'room'), 'room')); truth_value($boolean_value) ? (value_eq((($m->{'message'} // {})->{'text'} // undef), 'Party secret')) : $boolean_value } : $boolean_value }) } @{array_slice($opp->[0]->{'messages'}, $before_opp, undef)}))), 'Party-targeted chat does not leak to the enemy side');
    $host->locator('#chatBtn')->click();
    $host->locator('#chatOpponentToggle')->check();
    main::check((do { my $boolean_value = $host->locator('#chatOpponentToggle')->isChecked(); truth_value($boolean_value) ? (value_eq($host->locator('#chatSendBtn')->innerText(), 'SEND TO OPPONENT')) : $boolean_value }), 'Compact in-chat toggle switches outgoing messages explicitly to the opponent');
    $host->locator('#chatInput')->fill('Hello enemy side');
    $host->locator('#chatSendBtn')->click();
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
    $host->locator('#chatCloseBtn')->click();
    $opp->[0]->wait(sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'chat')); truth_value($boolean_value) ? do { my $boolean_value = (value_eq(($m->{'channel'} // undef), 'opponent')); truth_value($boolean_value) ? (value_eq($m->{'message'}->{'text'}, 'Hello enemy side')) : $boolean_value } : $boolean_value }); });
    main::check(JSON::PP::true, 'Opponent-targeted chat reaches the enemy side over the real server');
    $friend->locator('#chatBtn')->click();
    main::check((!(contains_value($friend->locator('#chatMessages')->innerText(), 'Hello enemy side'))), 'Opponent-targeted message does not leak to sender teammates');
    $friend->locator('#chatCloseBtn')->click();
    $host->locator('#soundBtn')->click();
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(220));
    $before_notify = evaluate_js($host, '__test.lastChatNotify');
    $opp->[0]->send({type => 'chat', channel => 'opponent', text => 'Enemy reply'});
    wait_js($host, 'document.querySelector(\'#chatBadge\').textContent===\'1\'');
    $after_notify = evaluate_js($host, '__test.lastChatNotify');
    main::check((do { my $boolean_value = $host->locator('#chatPanel')->isHidden(); truth_value($boolean_value) ? do { my $boolean_value = (value_eq($host->locator('#chatBadge')->innerText(), '1')); truth_value($boolean_value) ? (($after_notify > $before_notify)) : $boolean_value } : $boolean_value }), 'Incoming opponent message uses the integrated unread badge and notification path');
    $host->locator('#chatBtn')->click();
    wait_js($host, 'document.querySelector("#chatMessages").textContent.includes("Enemy reply")');
    $chat_text = $host->locator('#chatMessages')->innerText();
    main::check((do { my $boolean_value = (contains_value($chat_text, 'OPPONENT')); truth_value($boolean_value) ? (contains_value($chat_text, 'Enemy reply')) : $boolean_value }), 'Incoming enemy messages are visibly marked OPPONENT in the shared transcript');
    $host->locator('#chatCloseBtn')->click();
    $host->bringToFront();
    $host->keyboard()->down('f');
    $host->keyboard()->down('Space');
    $Leqra::Browser::HANDLE->await($host->waitForTimeout(80));
    $host->keyboard()->up('f');
    $host->keyboard()->up('Space');
    wait_js($host, '()=>{const s=leqra.getState(),me=s.online.id,p2=s.room.players.find(p=>p.kind===\'local\'&&p.owner===me),ts=__test.online.snapshots.at(-1).tanks;return p2&&[me,p2.id].every(id=>ts.find(t=>t.id===id)?.ack>0);}');
    main::check(JSON::PP::true, 'Primary F and secondary Space retain independent online input acknowledgements');
    main::check($host->locator('#weaponLabel2')->isVisible(), 'Player 2 ammo remains visible in matched gameplay');
    $host->locator('#roomBtn')->click();
    wait_js($host, '!document.querySelector("#onlineMenuScreen").hidden');
    main::check((do { my $boolean_value = (!(contains_value($host->locator('#onlineMenuScreen')->innerText(), 'BACK TO MY PARTY'))); truth_value($boolean_value) ? (value_eq($host->locator('#partyReturnMenuBtn')->count(), 0)) : $boolean_value }), 'Online match menu has no BACK TO MY PARTY action');
    main::check((value_eq(trim_text($host->locator('#returnRoomBtn')->innerText(), 'strip'), 'End match')), 'Online host action is labeled End match');
    $host->locator('#onlineReturnBtn')->click();
    wait_js($host, 'document.querySelector("#onlineMenuScreen").hidden');
    $friend->screenshot({path => format_value($out->child('matched-ctf-320.png'))});
    my $tuple_212_8 = main::load($b, 'Match Viewer', 390, 844, (('&room=' . $battle) . '&spectate=1'));
    $watch = $tuple_212_8->[0];
    $wc = $tuple_212_8->[1];
    wait_js($watch, 'document.querySelector("#joinDialog").open');
    $watch->locator('#pilotName')->fill('Match Viewer');
    $watch->locator('#joinRoomBtn')->click();
    wait_js($watch, 'leqra.getState().online?.spectating');
    main::check((value_eq(evaluate_js($watch, 'leqra.getState().online.code'), $battle)), 'Watch link joins matched arena as spectator after callsign confirmation');
    main::check((do { my $boolean_value = $watch->locator('#spectatorPlayBtn')->isDisabled(); truth_value($boolean_value) ? (value_eq($watch->locator('#spectatorPlayBtn')->innerText(), 'SPECTATING ONLY')) : $boolean_value }), 'Matched spectator HUD clearly disables new tank entry while remaining Spectating');
    main::check($watch->locator('#toggleSpectateBtn')->isDisabled(), 'Matched spectator room role control is disabled, not a failing action');
    main::check($watch->locator('#chatBtn')->isHidden(), 'Pure matchmaking spectators without a party or side do not get match chat');
    $old = evaluate_js($host, 'leqra.getState().online.id');
    evaluate_js($host, '__test.online.socket.close(4000,"queue reconnect test")');
    wait_js($host, '!leqra.getState().online.connected');
    wait_js($host, 'leqra.getState().online.connected', undef, {timeout => 15000});
    main::check((do { my $boolean_value = (value_eq(evaluate_js($host, 'leqra.getState().online.id'), $old)); truth_value($boolean_value) ? evaluate_js($host, 'leqra.getState().room.players.some(p=>p.kind==="local"&&p.name==="Keyboard Ally")') : $boolean_value }), 'Reconnect preserves both matched pilots and identities');
    for $p (@{$opp}) {
        leave_peer($p);
    }
    wait_js($host, 'leqra.getState().phase==="matchOver"', undef, {timeout => 10000});
    wait_js($host, 'document.querySelector("#victoryDialog").open');
    wait_js($friend, 'document.querySelector("#victoryDialog").open');
    wait_js($watch, 'document.querySelector("#victoryDialog").open');
    main::check((do { my $boolean_value = (contains_value($host->locator('#victoryTitle')->innerText(), 'WINS')); truth_value($boolean_value) ? $host->locator('#victoryStats')->isVisible() : $boolean_value }), 'Public forfeit resolves to a results screen with match statistics');
    main::check((do { my $boolean_value = (value_eq($host->locator('#victoryEyebrow')->innerText(), 'MATCH RESULTS')); truth_value($boolean_value) ? (!(contains_value(uc($host->locator('#victoryDialog')->innerText()), 'CONGRAT'))) : $boolean_value }), 'Results screen avoids congratulating non-winners while still identifying the winning side');
    main::check((do { my $boolean_value = $host->locator('#victoryAgainBtn')->isVisible(); truth_value($boolean_value) ? do { my $boolean_value = (index($host->locator('#victoryAgainBtn')->innerText(), 'REMATCH') == 0); truth_value($boolean_value) ? do { my $boolean_value = (contains_value((do { my $boolean_value = $host->locator('#victoryAgainBtn')->getAttribute('class'); truth_value($boolean_value) ? $boolean_value : '' }), 'queue-rematch')); truth_value($boolean_value) ? (value_eq(evaluate_js($host->locator('#victoryAgainBtn'), 'e=>getComputedStyle(e).backgroundColor'), 'rgb(57, 255, 136)')) : $boolean_value } : $boolean_value } : $boolean_value }), 'Queued participant gets the neon green REMATCH action');
    main::check((($host->locator('#victoryCloseBtn')->boundingBox()->{'x'} < $host->locator('#victoryAgainBtn')->boundingBox()->{'x'})), 'BACK TO ROOM is left of REMATCH on queued results');
    main::check((do { my $boolean_value = (value_eq($host->locator('#victoryPartyBtn')->count(), 0)); truth_value($boolean_value) ? $watch->locator('#victoryAgainBtn')->isHidden() : $boolean_value }), 'Legacy result party button is removed and spectators cannot rematch');
    $host->screenshot({path => format_value($out->child('matched-results.png'))});
    $host->locator('#victoryCloseBtn')->click();
    wait_js($host, '(code)=>leqra.getState().online.code===code', $home, {});
    main::check((value_eq(evaluate_js($host, 'leqra.getState().room.awayMatch'), $battle)), 'Returning early reserves the lobby until remaining friend returns');
    main::check($host->locator('#toggleSpectateBtn')->isDisabled(), 'Reserved source lobby disables role changes until friends return');
    $friend->locator('#victoryCloseBtn')->click();
    wait_js($friend, '(code)=>leqra.getState().online.code===code', $home, {});
    wait_js($host, '!leqra.getState().room.awayMatch');
    $r = evaluate_js($host, 'leqra.getState().room');
    main::check((do { my $boolean_value = (value_eq(scalar(@{$r->{'players'}}), 6)); truth_value($boolean_value) ? (value_eq(sum(@{[map { my $p = $_; (value_eq($p->{'kind'}, 'bot')) } @{$r->{'players'}}]}), 3)) : $boolean_value }), 'Return restores private bot roster and three real players');
    main::check((do { my $boolean_value = (value_eq($r->{'rules'}->{'teamMode'}, 'ffa')); truth_value($boolean_value) ? (value_eq($r->{'rules'}->{'mapSize'}, 'large')) : $boolean_value }), 'Private Free-for-all rules and default map were not overwritten');
    main::check(scalar(grep { my $p = $_; (do { my $boolean_value = (value_eq($p->{'name'}, 'Keyboard Ally')); truth_value($boolean_value) ? (value_eq($p->{'kind'}, 'local')) : $boolean_value }) } @{$r->{'players'}}), 'Player 2 custom callsign survives battle and return');
    main::check((defined($observer->wait(sub { my ($m) = @_; return (do { my $boolean_value = (value_eq($m->{'type'}, 'room')); truth_value($boolean_value) ? (!truth_value(($m->{'awayMatch'} // undef))) : $boolean_value }); }))), 'Original spectator stays in the private room');
    $host->locator('#matchmakingBtn')->click();
    $host->locator('[data-queue="ctf-3"]')->click();
    $host->locator('#queueStartBtn')->click();
    wait_js($host, 'leqra.getState().room.queue?.stage==="confirming"');
    wait_js($friend, 'document.querySelector("#queueAcceptBtn").offsetParent!==null');
    main::check(JSON::PP::true, 'Another match requires fresh remote consent, not stale previous readiness');
    $friend->locator('#queueCancelBtn')->click();
    wait_js($host, '!leqra.getState().room.queue');
    main::check(JSON::PP::true, 'A participating friend can cancel the next party search');
    main::check((!truth_value($errors)), 'No uncaught browser errors');
    for $c (@{[$hc, $fc, $wc]}) {
        $c->close();
    }
    $report = {'version' => match_re('GAME_VERSION=\'([^\']+)\'', $js)->[1], 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limitations' => 'Chromium desktop/mobile emulation; exact assets; synthetic Location/History/storage; real local Go sockets. No physical phones or public deployment.'};
    $out->child('results.json')->spew_utf8(json_text($report, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
for $p (@{$peers}) {
    leave_peer($p);
}
$b->close();
die $caught_error if $caught_error;
