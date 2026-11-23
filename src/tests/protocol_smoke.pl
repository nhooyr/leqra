#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;
use utf8;
binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";
use FindBin;
use lib "$FindBin::Bin/lib";
use Path::Tiny qw(path);
use File::Path qw(make_path);
use JSON::PP;
use List::Util qw(min max sum);
use URI;
use Leqra::Protocol qw(peer connect_socket upgrade_status http_json http_status pause write_text token_hex json_text same close_peers);
$| = 1;
my $BASE = shift(@ARGV) // 'http://localhost:8080';
$BASE =~ s{/+$}{};
my $ORIGIN = URI->new($BASE); $ORIGIN->path(''); $ORIGIN->query(undef); $ORIGIN = "$ORIGIN";
# Optional live integration checks. Run a server, then:
# Install optional Perl harness dependencies with cpanm --installdeps .
# perl tests/protocol_smoke.pl http://localhost:8080
# The game itself does not depend on these harness modules.

my $checks = [];

my $check;
$check = sub {
    my ($condition, $name) = @_;
    die json_text($name) . "\n" unless $condition;
    push(@{$checks}, $name);
    print(join(" ", "PASS", $name), "\n");
};

my $peer = sub { Leqra::Protocol::peer($BASE) };

my $main;
$main = sub {
    my ($accepted, $ack, $b, $before, $cl, $code, $created_welcome, $creator, $creators, $err, $expected, $fresh, $hostPilot, $i, $invalid, $kickedResume, $label, $leaked, $m, $missing_code, $moving, $msg, $named_code, $notice, $origin, $other, $own, $p, $payload, $peers, $pong, $r, $racers, $reconnect, $rejected, $replies, $resumed, $resumedWelcome, $roster, $s, $stateAfter, $states, $t, $target, $token, $unused, $viewer, $w, $welcome, $welcomes, $ws);
    $peers = [];
    eval {
        for $unused (@{[0 .. 6 - 1]}) {
            push(@{$peers}, $peer->());
        }
        $peers->[0]->send({"type" => "create", "name" => "HOST"});
        $welcome = $peers->[0]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $code = $welcome->{"room"};
        $welcomes = [$welcome];
        for $i (@{[1 .. 4 - 1]}) {
            $peers->[$i]->send({"type" => "join", "code" => $code, "name" => ("PILOT " . $i)});
            push(@{$welcomes}, $peers->[$i]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }));
        }
        $check->(((scalar(keys %{{ map { $_ => 1 } (map { my $m = $_; $m->{"id"} } @{$welcomes}) }}) == 4)), "Four unique player seats");
        $check->(((scalar(keys %{{ map { $_ => 1 } (map { my $m = $_; $m->{"token"} } @{$welcomes}) }}) == 4)), "Independent private reconnect credentials");
        $peers->[4]->send({"type" => "join", "code" => $code});
        $viewer = $peers->[4]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $check->(($viewer->{"spectating"} && $viewer->{"full"} && (($viewer->{"id"} >= 4))), "Fifth visitor enters as spectator");
        $peers->[5]->send({"type" => "create", "name" => "OTHER ROOM"});
        $other = $peers->[5]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $check->((($other->{"room"} ne $code)), "Separate room code");
        $peers->[1]->send({"type" => "start"});
        $err = $peers->[1]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); });
        $check->((($err->{"code"} eq "not_host")), "Non-host cannot start match");
        $peers->[0]->send({"type" => "start"});
        $err = $peers->[0]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); });
        $check->((($err->{"code"} eq "not_ready")), "Readiness required before starting");
        for $cl (@{[@{$peers}[0 .. (4 - 1)]]}) {
            $cl->send({"type" => "ready", "ready" => JSON::PP::true});
        }
        $peers->[0]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && $m->{"canStart"}); });
        $peers->[0]->send({"type" => "start"});
        $states = [map { my $cl = $_; $cl->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (exists($m->{"world"}))); }) } @{[@{$peers}[0 .. (4 - 1)]]}];
        $check->((!grep { !$_ } @{[map { my $s = $_; (same($s->{"world"}, $states->[0]->{"world"})) } @{$states}]}), "Identical authoritative maze on all four clients");
        $check->((!grep { !$_ } @{[map { my $s = $_; ((scalar(@{$s->{"tanks"}}) == 4)) } @{$states}]}), "Four tanks spawn on server");
        $peers->[0]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "playing"))); });
        $before = scalar(@{$peers->[0]->{"messages"}});
        $peers->[0]->send({"type" => "input", "seq" => 1, "right" => JSON::PP::true, "fire" => JSON::PP::true, "x" => 999999, "y" => 999999, "scores" => [5, 0, 0, 0], "winner" => 0});
        pause(0.22);
        $moving = $peers->[0]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $b = $_; (($b->{"owner"} == 0)) } @{$m->{"bullets"}}]})); }, "after" => $before);
        $check->((!grep { !$_ } @{[map { my $s = $_; (($s == 0)) } @{$moving->{"scores"}}]}), "Client-supplied scores ignored");
        $own = ([map { my $t = $_; (($t->{"id"} == 0)) ? ($t) : () } @{$moving->{"tanks"}}]->[0] // undef);
        $check->((((0 <= $own->{"x"}) && ($own->{"x"} <= $states->[0]->{"world"}->{"width"})) && ((0 <= $own->{"y"}) && ($own->{"y"} <= $states->[0]->{"world"}->{"height"}))), "Client-supplied positions ignored");
        $check->(scalar(grep { $_ } @{[map { my $b = $_; (($b->{"owner"} == 0)) } @{$moving->{"bullets"}}]}), "Input produces server-owned shots");
        $check->(!(scalar(grep { $_ } @{[map { my $m = $_; (($m->{"type"} eq "state")) ? ((scalar(grep { same($_, ($m->{"phase"} // undef)) } @{["playing", "countdown"]}))) : () } @{$peers->[5]->{"messages"}}]})), "Other room remains isolated");
        $before = scalar(@{$peers->[0]->{"messages"}});
        $peers->[0]->send({"type" => "ping", "t" => 123.5});
        $pong = $peers->[0]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "pong")); }, "after" => $before);
        $check->((($pong->{"t"} == 123.5)), "Application latency ping echoed");
        $peers->[3]->send_fragments("{\"type\":\"ping\",", "\"t\":456}");
        $pong = $peers->[3]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "pong")) && (($m->{"t"} == 456))); });
        $peers->[3]->ping("test");
        $check->((($pong->{"t"} == 456)), "Fragmented text and WebSocket ping/pong interoperable");
        $peers->[1]->close();
        $peers->[0]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && scalar(grep { $_ } @{[map { my $p = $_; ((($p->{"id"} == 1)) && !($p->{"connected"})) } @{$m->{"players"}}]})); });
        $resumed = $peer->();
        push(@{$peers}, $resumed);
        $resumed->send({"type" => "join", "code" => $code, "token" => $welcomes->[1]->{"token"}, "name" => "IGNORED RENAMING"});
        $resumedWelcome = $resumed->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $check->(($resumedWelcome->{"resumed"} && (($resumedWelcome->{"id"} == 1))), "Reconnect preserves player identity");
        $s = $resumed->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (exists($m->{"world"}))); });
        $check->((($s->{"generation"} == $states->[0]->{"generation"})), "Reconnect restores existing match and maze");
        $leaked = scalar(grep { $_ } @{[map { my $cl = $_; map { my $m = $_; (($m->{"type"} ne "welcome")) ? (map { my $token = $_; ((index(json_text($m), $token) >= 0)) } @{[map { my $w = $_; $w->{"token"} } @{$welcomes}]}) : () } @{$cl->{"messages"}} } @{[@{$peers}[0 .. (4 - 1)]]}]});
        $check->(!($leaked), "Reconnect tokens never appear in public broadcasts");
        $peers->[0]->close();
        $r = $resumed->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && (($m->{"host"} == 1))); });
        $check->((($r->{"host"} == 1)), "Host transfers after disconnect");
        $target = ([map { my $p = $_; (($p->{"id"} == 2)) ? ($p) : () } @{$r->{"players"}}]->[0] // undef);
        $check->((($target->{"member"} > 0)), "Room publishes a non-secret seat-incarnation ID");
        $before = scalar(@{$peers->[3]->{"messages"}});
        $peers->[3]->send({"type" => "kick", "target" => 2, "member" => $target->{"member"}});
        $err = $peers->[3]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "error")) && same(($m->{"action"} // undef), "kick")); }, "after" => $before);
        $check->((($err->{"code"} eq "not_host")), "Production server rejects guest kick");
        $hostPilot = ([map { my $p = $_; (($p->{"id"} == 1)) ? ($p) : () } @{$r->{"players"}}]->[0] // undef);
        $before = scalar(@{$resumed->{"messages"}});
        $resumed->send({"type" => "kick", "target" => 1, "member" => $hostPilot->{"member"}});
        $err = $resumed->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "error")) && same(($m->{"action"} // undef), "kick")); }, "after" => $before);
        $check->((($err->{"code"} eq "kick_self")), "Production server rejects host self-kick");
        $before = scalar(@{$resumed->{"messages"}});
        $resumed->send({"type" => "kick", "target" => 2, "member" => ($target->{"member"} + 100)});
        $err = $resumed->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "error")) && same(($m->{"action"} // undef), "kick")); }, "after" => $before);
        $check->((($err->{"code"} eq "player_missing")), "Production server rejects stale target incarnation");
        $before = scalar(@{$peers->[3]->{"messages"}});
        $resumed->send({"type" => "kick", "target" => 2, "member" => $target->{"member"}});
        $ack = $resumed->wait(sub { my ($m) = @_; return (($m->{"type"} eq "player_kicked")); });
        $check->(((($ack->{"id"} == 2)) && (($ack->{"member"} == $target->{"member"}))), "New host receives the correct kick acknowledgement");
        $notice = $peers->[2]->wait(sub { my ($m) = @_; return (($m->{"type"} eq "kicked")); });
        $check->((($notice->{"room"} eq $code)), "Kicked player receives terminal room-removal notice");
        $roster = $peers->[3]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && (!grep { !$_ } @{[map { my $p = $_; (($p->{"id"} != 2)) } @{$m->{"players"}}]})); }, "after" => $before);
        $check->((($roster->{"host"} == 1)), "Remaining players receive the updated roster without host reset");
        $stateAfter = $peers->[3]->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $t = $_; ((($t->{"id"} == 2)) && !($t->{"alive"})) } @{$m->{"tanks"}}]})); }, "after" => $before);
        $check->(!(scalar(grep { $_ } @{[map { my $b = $_; (($b->{"owner"} == 2)) } @{$stateAfter->{"bullets"}}]})), "Removed tank is eliminated and owns no live shots");
        $kickedResume = $peer->();
        push(@{$peers}, $kickedResume);
        $kickedResume->send({"type" => "join", "code" => $code, "token" => $welcomes->[2]->{"token"}});
        $notice = $kickedResume->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["kicked", "welcome", "error"]})); });
        $check->((($notice->{"type"} eq "kicked")), "Revoked token gets a terminal notice, not a resumable seat or invite fallback");
        $before = scalar(@{$peers->[2]->{"messages"}});
        $peers->[2]->send({"type" => "join", "code" => $code, "name" => "RETRY"});
        $notice = $peers->[2]->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["kicked", "welcome", "error"]})); }, "after" => $before);
        $check->((($notice->{"type"} eq "kicked")), "Removed socket cannot silently rejoin");
        $named_code = join("", @{[map { my $unused = $_; substr("ABCDEFGHJKLMNPQRSTUVWXYZ23456789", int(rand(length("ABCDEFGHJKLMNPQRSTUVWXYZ23456789"))), 1) } @{[0 .. 6 - 1]}]});
        $racers = [map { my $unused = $_; $peer->() } @{[0 .. 5 - 1]}];
        push(@{$peers}, @{$racers});
        for my $item (@{[map { [$_, $racers->[$_]] } 0 .. $#{$racers}]}) {
            ($i, $cl) = @{$item};
            $cl->send({"type" => "join", "code" => lc($named_code), "name" => ("RACER " . $i)});
        }
        $replies = [map { my $cl = $_; $cl->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["welcome", "error"]})); }) } @{$racers}];
        $accepted = [map { my ($cl, $msg) = @{$_}; (($msg->{"type"} eq "welcome")) ? ([$cl, $msg]) : () } @{[map { my $i = $_; [$racers->[$i], $replies->[$i]] } 0 .. min($#{$racers}, $#{$replies})]}];
        $rejected = [map { my $msg = $_; (($msg->{"type"} eq "error")) ? ($msg) : () } @{$replies}];
        $check->((((scalar(@{$accepted}) == 5)) && !(scalar(@{$rejected})) && ((sum(@{[map { my ($unused, $w) = @{$_}; !($w->{"spectating"}) } @{$accepted}]}) == 4))), "Simultaneous named joins admit four tanks and a spectator");
        $check->((!grep { !$_ } @{[map { my ($unused, $msg) = @{$_}; (($msg->{"room"} eq $named_code)) } @{$accepted}]}), "Concurrent joins preserve the requested normalized code");
        $creators = [map { my ($cl, $msg) = @{$_}; $msg->{"created"} ? ([$cl, $msg]) : () } @{$accepted}];
        $check->(((scalar(@{$creators}) == 1)), "Exactly one concurrent join creates the room");
        ($creator, $created_welcome) = @{$creators->[0]};
        $roster = $creator->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && ((scalar(@{$m->{"players"}}) == 4))); });
        $check->((($roster->{"host"} == $created_welcome->{"id"})), "First successful named join is the sole room host");
        $check->(((scalar(keys %{{ map { $_ => 1 } (map { my ($unused, $msg) = @{$_}; $msg->{"token"} } @{$accepted}) }}) == 5)), "Auto-created room has independent private credentials");
        $check->(((($roster->{"phase"} eq "lobby")) && !($roster->{"canStart"})), "Auto-created room preserves ready-up and start rules");
        $missing_code = join("", @{[map { my $unused = $_; substr("ABCDEFGHJKLMNPQRSTUVWXYZ23456789", int(rand(length("ABCDEFGHJKLMNPQRSTUVWXYZ23456789"))), 1) } @{[0 .. 6 - 1]}]});
        $reconnect = $peer->();
        push(@{$peers}, $reconnect);
        $reconnect->send({"type" => "join", "code" => $missing_code, "token" => "gone-session"});
        $err = $reconnect->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["error", "welcome"]})); });
        $check->(same(($err->{"code"} // undef), "room_missing"), "Missing-room background resume is rejected without creating a room");
        $before = scalar(@{$reconnect->{"messages"}});
        $reconnect->send({"type" => "join", "code" => $missing_code, "name" => "FRESH HOST"});
        $fresh = $reconnect->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, "after" => $before);
        $check->(($fresh->{"created"} && (($fresh->{"room"} eq $missing_code)) && (($fresh->{"id"} == 0))), "Explicit fresh join creates the missing room after failed resume");
        $check->(((($fresh->{"token"} ne "gone-session")) && !($fresh->{"resumed"})), "New room receives fresh credentials, not expired identity");
        $invalid = $peer->();
        push(@{$peers}, $invalid);
        $invalid->send({"type" => "join", "code" => "invalid\x{0000}name"});
        $err = $invalid->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["error", "welcome"]})); });
        $check->(same(($err->{"code"} // undef), "bad_code"), "Invalid room codes still fail rather than creating rooms");
        for $origin (@{["https://evil.invalid", "null"]}) {
            $check->(upgrade_status($BASE, origin => $origin) == 403, "Cross-origin upgrade rejected: $origin");
        }
        for my $item (@{[["binary", 1003, "Binary frames rejected"], [("x" x 2049), 1009, "Oversized message rejected"], ["{", 1007, "Malformed JSON rejected"], ["{\"type\":\"cheat\"}", 1008, "Unknown command rejected"]]}) {
            ($payload, $expected, $label) = @{$item};
            $ws = connect_socket($BASE, "origin" => $ORIGIN);
            if ($expected == 1003) {
                $ws->send_binary($payload);
            } else {
                $ws->send_text($payload);
            }
            $ws->wait_closed(3);
            $check->(((defined($ws->{close_code})) && (($ws->{close_code} == $expected))), $label);
            $ws->close();
        }
        print(join(" ", JSON::PP->new->canonical->pretty->encode({"checks_passed" => scalar(@{$checks}), "checks" => $checks})), "\n");
    1;
    };
    my $caught_error = $@;
    for $cl (@{$peers}) {
        $cl->close();
    }
    die $caught_error if $caught_error;
};

eval { $main->() };
my $error = $@;
close_peers();
die $error if $error;
