#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Leqra::Protocol qw(peer http_json http_status pause write_text json_text same close_peers);

# Historical v4.0 production matchmaking checks, using real HTTP/WebSocket handlers.
my $expect_version = '4.0.0';
my $output = 'matchmaking-protocol.json';
my $help;
GetOptions('expect-version=s' => \$expect_version, 'output=s' => \$output, 'help' => \$help)
    or die "Usage: matchmaking_protocol.pl URL [--expect-version VERSION] [--output FILE]\n";
if ($help) { print "Usage: matchmaking_protocol.pl URL [--expect-version VERSION] [--output FILE]\n"; exit; }
@ARGV == 1 or die "Usage: matchmaking_protocol.pl URL [--expect-version VERSION] [--output FILE]\n";
my $base = shift;
$base =~ s{/+$}{};
my @checks;
$| = 1;
sub check { my ($ok, $label) = @_; die "$label\n" unless $ok; push @checks, $label; print "PASS $label\n"; }
sub new_peer { peer($base, action_interval => .16, timeout => 12, max_size => 2_000_000) }
sub close_party_peer { my ($p) = @_; eval { $p->send({type => 'leave'}) }; $p->close; }
sub party {
    my ($count, $name) = @_;
    my @players = map { new_peer() } 1 .. $count;
    my $welcome = $players[0]->op('create', sub { $_[0]{type} eq 'welcome' }, name => "${name}0");
    my $code = $welcome->{room};
    my @welcomes = ($welcome);
    for my $i (1 .. $#players) {
        push @welcomes, $players[$i]->op('join', sub { $_[0]{type} eq 'welcome' }, code => $code, name => "$name$i");
    }
    return (\@players, $code, \@welcomes);
}
sub queue {
    my ($players, $key) = @_;
    my $room = $players->[0]->op('queue_join', sub { $_[0]{type} eq 'room' && $_[0]{queue} }, queue => $key);
    my $id = $room->{queue}{id};
    for my $i (1 .. $#$players) {
        $players->[$i]->op('queue_accept', sub { $_[0]{type} eq 'room' && $_[0]{queue} }, queueId => $id, ready => JSON::PP::true);
    }
    return $id;
}
sub team_set { my ($room, $prefix) = @_; return {map { $_->{team} => 1 } grep { index($_->{name}, $prefix) == 0 } @{$room->{players}}}; }
sub run {
    my $config = http_json("$base/api/config");
    my $health = http_json("$base/healthz");
    check($health->{version} eq $expect_version && $config->{matchmaking} && @{$config->{queues}} == 6,
        'Production health/config expose six supported queues');
    check(http_status("$base/__test/grant") == 404, 'Test-only grant endpoint is absent from production');
    for my $definition (@{$config->{queues}}) {
        my (@groups, @homes, @welcomes);
        my @sizes = $definition->{teamSize} == 0 ? ((1) x 8) : (($definition->{teamSize}) x 2);
        for my $i (0 .. $#sizes) {
            my ($players, $home, $welcomes) = party($sizes[$i], "Q$i-");
            push @groups, $players; push @homes, $home; push @welcomes, @$welcomes;
            queue($players, $definition->{key});
        }
        my @everyone = map { @$_ } @groups;
        my @transfers = map { $_->wait(sub { $_[0]{type} eq 'welcome' && ($_[0]{transfer} // '') eq 'match_found' }) } @everyone;
        my %codes = map { $_->{room} => 1 } @transfers;
        check(keys(%codes) == 1 && !grep($codes{$_}, @homes), "$definition->{key}: full queue assembles one fresh battle");
        my $code = $transfers[0]{room};
        my $room = $everyone[0]->wait(sub { $_[0]{type} eq 'room' && $_[0]{code} eq $code });
        my %teams; ++$teams{$_->{team}} for @{$room->{players}};
        check(@{$room->{players}} == $definition->{players} && !grep($_->{kind} eq 'bot', @{$room->{players}}), "$definition->{key}: exact human-only population");
        my $expected_teams = $definition->{teamSize} == 0 ? {0 => 8} : {1 => $definition->{teamSize}, 2 => $definition->{teamSize}};
        check(same(\%teams, $expected_teams), "$definition->{key}: balanced teams or eight independent FFA sides");
        check($room->{host} == -1 && $room->{matchmaking}{locked} && !$room->{canStart}, "$definition->{key}: no player can control the public match");
        check($room->{rules}{mode} eq $definition->{mode} && $room->{rules}{mapSize} eq $definition->{map}, "$definition->{key}: fixed mode and map applied");
        my $state = $everyone[0]->wait(sub { $_[0]{type} eq 'state' && $_[0]{world} && $_[0]{world}{cols} == $definition->{cols} && @{$_[0]{tanks}} == $definition->{players} });
        check($state->{world}{rows} == $definition->{rows}, "$definition->{key}: full authoritative map received");
        for my $players (@groups) {
            my %assigned;
            for my $player (@$players) {
                my ($welcome) = grep { ($_->{transfer} // '') eq 'match_found' } @{$player->{messages}};
                my ($member) = grep { $_->{id} == $welcome->{id} } @{$room->{players}};
                $assigned{$member->{team}} = 1;
            }
            check(keys(%assigned) == 1, "$definition->{key}: each original party stays on one side");
        }
        $everyone[0]->wait(sub { $_[0]{type} eq 'state' && $_[0]{phase} eq 'playing' }, timeout => 10);
        check(1, "$definition->{key}: starts automatically after countdown, no host click");
        my $error = $everyone[0]->op('start', sub { $_[0]{type} eq 'error' }, scores => [(99) x 8]);
        check($error->{code} eq 'match_locked', "$definition->{key}: forged host start rejected");
        my @tokens = map { $_->{token} } @welcomes;
        my $leaked = 0;
        for my $player (@everyone) { for my $message (@{$player->{messages}}) {
            next if $message->{type} eq 'welcome';
            my $json = json_text($message);
            $leaked ||= grep { index($json, $_) >= 0 } @tokens;
        } }
        check(!$leaked, "$definition->{key}: no credentials in shared state");
        for my $i (0 .. $#groups) { for my $player (@{$groups[$i]}) {
            my $welcome = $player->op('return_party', sub { $_[0]{type} eq 'welcome' && ($_[0]{transfer} // '') eq 'party_return' });
            check($welcome->{room} eq $homes[$i], "$definition->{key}: member returns to their own original lobby");
        } }
        close_party_peer($_) for @everyone;
    }
    my ($a, $home, $aw) = party(2, 'PartyA');
    my ($solo) = party(1, 'Solo');
    my ($trio) = party(3, 'PartyB');
    my $error = $a->[1]->op('queue_join', sub { $_[0]{type} eq 'error' }, queue => 'ctf-3');
    check($error->{code} eq 'not_host', 'Guest cannot initiate party search');
    for my $key ('elimination-1', 'ffa-8', 'not-a-queue') {
        $error = $a->[0]->op('queue_join', sub { $_[0]{type} eq 'error' }, queue => $key);
        check(scalar(grep($_ eq $error->{code}, qw(party_too_large ffa_solo bad_queue))), "Invalid/undersized queue rejected: $key");
    }
    my $room = $a->[0]->op('queue_join', sub { $_[0]{type} eq 'room' && $_[0]{queue} }, queue => 'ctf-3');
    my $qid = $room->{queue}{id};
    check($room->{queue}{stage} eq 'confirming', 'Remote friends must consent before the ticket searches');
    $solo->[0]->send({type => 'queue_info'});
    my $catalog = $solo->[0]->wait(sub { $_[0]{type} eq 'queue_catalog' });
    my ($entry) = grep { $_->{definition}{key} eq 'ctf-3' } @{$catalog->{queues}};
    check($entry->{waitingPlayers} == 0, 'Unconfirmed party is not counted as searching');
    my $late = new_peer();
    my $welcome = $late->op('join', sub { $_[0]{type} eq 'welcome' }, code => $home, name => 'Observer');
    check($welcome->{spectating} && $welcome->{busy}, 'New visitor cannot mutate a queued party: enters spectator');
    $error = $late->op('queue_cancel', sub { $_[0]{type} eq 'error' }, queueId => $qid);
    check($error->{code} eq 'not_participant', 'Spectator cannot cancel another party search');
    $a->[1]->op('queue_cancel', sub { $_[0]{type} eq 'queue_cancelled' }, queueId => $qid);
    check(1, 'Queued friend can cancel the whole party search');
    $room = $a->[0]->op('queue_join', sub { $_[0]{type} eq 'room' && $_[0]{queue} }, queue => 'ctf-3');
    my $qid2 = $room->{queue}{id};
    $error = $a->[1]->op('queue_accept', sub { $_[0]{type} eq 'error' }, queueId => $qid, ready => JSON::PP::true);
    check($error->{code} eq 'stale_queue', 'Old confirmation cannot accept a new invitation');
    $a->[1]->op('queue_accept', sub { $_[0]{type} eq 'room' && $_[0]{queue} && $_[0]{queue}{stage} eq 'searching' }, queueId => $qid2, ready => JSON::PP::true);
    queue($solo, 'ctf-3'); queue($trio, 'ctf-3');
    $welcome = $a->[0]->wait(sub { ($_[0]{transfer} // '') eq 'match_found' });
    my $code = $welcome->{room};
    $room = $a->[0]->wait(sub { $_[0]{type} eq 'room' && $_[0]{code} eq $code });
    my ($at, $st, $bt) = map { team_set($room, $_) } ('PartyA', 'Solo', 'PartyB');
    check(keys(%$at) == 1 && same($at, $st) && !same($at, $bt), 'Mixed-sized tickets pack 2+1 versus 3 without splitting friends');
    $late->wait(sub { $_[0]{type} eq 'room' && ($_[0]{awayMatch} // '') eq $code });
    check(1, 'Private spectator remains home and sees match watch reference');
    my $viewer = new_peer();
    my $vw = $viewer->op('join', sub { $_[0]{type} eq 'welcome' }, code => $code, name => 'Match Viewer');
    check($vw->{spectating}, 'Fresh match link visitor cannot replace a contestant');
    $error = $viewer->op('spectate', sub { $_[0]{type} eq 'error' }, spectating => JSON::PP::false);
    check($error->{code} eq 'match_locked', 'Matched spectator cannot claim a seat');
    $error = $viewer->op('return_party', sub { $_[0]{type} eq 'error' });
    check($error->{code} eq 'no_party', 'Unrelated viewer cannot return into a private origin');
    my $party_start = @{$a->[1]{messages}};
    my $viewer_start = @{$viewer->{messages}};
    $a->[0]->send({type => 'chat', text => 'Matched together'});
    $a->[1]->wait(sub { $_[0]{type} eq 'chat' && ($_[0]{channel} // 'room') eq 'room' && $_[0]{message}{text} eq 'Matched together' }, after => $party_start);
    check(1, 'Matched normal chat stays with the travelling party');
    pause(.1);
    check(!grep($_->{type} eq 'chat' && $_->{message}{text} eq 'Matched together', @{$viewer->{messages}}[$viewer_start .. $#{$viewer->{messages}}]), 'Unrelated match spectators do not receive private party chat');
    check(!grep($_->{type} eq 'chat' && $_->{message}{text} eq 'Matched together', @{$late->{messages}}), 'Matched party chat does not leak into the source lobby');
    my $old_id = $welcome->{id};
    $a->[0]->close();
    my $fresh = new_peer();
    my $resumed = $fresh->op('join', sub { $_[0]{type} eq 'welcome' }, code => $home, token => $aw->[0]{token}, name => 'Ignored');
    check($resumed->{resumed} && $resumed->{room} eq $code && $resumed->{id} == $old_id, 'Origin credential safely follows an in-progress match transfer');
    $a->[0] = $fresh;
    close_party_peer($_) for @$trio;
    my $end = $a->[0]->wait(sub { $_[0]{type} eq 'state' && $_[0]{phase} eq 'matchOver' });
    check(defined($end->{matchStats}), 'Forfeit retains authoritative finished statistics');
    $resumed = $a->[0]->op('return_party', sub { ($_[0]{transfer} // '') eq 'party_return' });
    check($resumed->{room} eq $home, 'Surviving party returns without a new WebSocket');
    $a->[1]->op('return_party', sub { ($_[0]{transfer} // '') eq 'party_return' });
    $room = $a->[0]->wait(sub { $_[0]{type} eq 'room' && $_[0]{code} eq $home && !$_[0]{awayMatch} });
    check(@{$room->{players}} == 2, 'Original friend roster restored with no duplicates');
    close_party_peer($_) for (@$a, @$solo, $late, $viewer);
    write_text($output, JSON::PP->new->pretty->encode({version => $expect_version, passed => scalar(@checks), checks => \@checks, limits => 'Real loopback production HTTP/WebSocket handlers. No fixture grants, public hosting, region/skill matching, or deployment load test.'}));
    print 'TOTAL ', scalar(@checks), "\n";
}
eval { run(); 1 };
my $error = $@;
close_peers();
die $error if $error;
