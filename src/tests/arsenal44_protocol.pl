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
# Production endpoint checks: palette authority, snapshot compatibility and pickups.
# Run against a real production Go binary: perl tests/arsenal44_protocol.pl URL

my $main;
$main = sub {
    my ($b, $bad, $checks, $code, $e, $gh, $gid, $gr, $guest, $hello, $host, $invalid, $label, $member, $n, $output, $p, $path, $peers, $r, $report, $rules, $s, $t, $tank, $tanks, $target, $vh, $viewer, $who);
    $checks = [];
    $peers = [];
    my $check;
    $check = sub {
        my ($ok, $label) = @_;
        die json_text($label) . "\n" unless $ok;
        push(@{$checks}, $label);
        print(join(" ", "PASS", $label), "\n");
    };
    my $peer;
    $peer = sub {
        my ($p);
        $p = Leqra::Protocol::peer($BASE);
        push(@{$peers}, $p);
        return $p;
    };
    my $op;
    $op = sub {
        my ($p, $kind, $pred) = @_;
        my ($n);
        $pred //= undef;
        my $kw = $_[3] // {};
        pause(0.18);
        $n = scalar(@{$p->{"messages"}});
        $p->send({"type" => $kind, %{$kw}});
        return $p->wait(($pred || sub { my ($s) = @_; return (($s->{"type"} eq "room")); }), "after" => $n);
    };
    eval {
        $check->(((http_json(($BASE . "/healthz"))->{"version"} eq "4.4.0")), "Production binary reports 4.4.0");
        for $path (@{["/_fixture/arsenal44", "/_fixture/combat42"]}) {
            my $e = {code => http_status(($BASE . $path))};
            $check->((($e->{"code"} == 404)), (("No production " . $path) . " endpoint"));
        }
        $host = $peer->();
        $hello = $op->($host, "create", sub { my ($s) = @_; return (($s->{"type"} eq "welcome")); }, {"name" => "HOST"});
        $code = $hello->{"room"};
        $r = $host->wait(sub { my ($s) = @_; return (($s->{"type"} eq "room")); });
        $check->((same($r->{"rules"}->{"teamColors"}, [0, 1, 2, 3])), "Four backward-compatible default team colors");
        $guest = $peer->();
        $gh = $op->($guest, "join", sub { my ($s) = @_; return (($s->{"type"} eq "welcome")); }, {"name" => "FRIEND", "code" => $code});
        $viewer = $peer->();
        $vh = $op->($viewer, "join", sub { my ($s) = @_; return (($s->{"type"} eq "welcome")); }, {"name" => "WATCHER", "code" => $code, "spectating" => JSON::PP::true});
        $check->($vh->{"spectating"}, "Spectator can observe styled room");
        $r = $host->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "room")) && ((scalar(@{$s->{"players"}}) == 2)) && ((scalar(@{$s->{"spectators"}}) == 1))); });
        $target = ([map { my $p = $_; (($p->{"id"} == $gh->{"id"})) ? ($p) : () } @{$r->{"players"}}]->[0] // undef);
        $gid = $target->{"id"};
        $member = $target->{"member"};
        for my $item (@{[[$guest, "guest"], [$viewer, "spectator"]]}) {
            ($who, $label) = @{$item};
            $e = $op->($who, "configure", sub { my ($s) = @_; return (($s->{"type"} eq "error")); }, {"target" => $gid, "member" => $member, "colorIndex" => 7});
            $check->((($e->{"code"} eq "not_host")), ($label . " cannot forge tank palette changes"));
        }
        for $invalid (@{[(-2), 8, 99]}) {
            $e = $op->($host, "configure", sub { my ($s) = @_; return (($s->{"type"} eq "error")); }, {"target" => $gid, "member" => $member, "colorIndex" => $invalid});
            $check->((($e->{"code"} eq "bad_color")), ("Out-of-palette index rejected: " . $invalid));
        }
        $rules = {%{$r->{"rules"}}};
        %{$rules} = (%{$rules}, "teamMode" => "teams", "teamColors" => [6, 4, 3, 7], "weapons" => ["shield"], "pickupRate" => "superfast");
        $bad = {%{$rules}, "teamColors" => [0, 1, 2, 8]};
        $e = $op->($host, "rules", sub { my ($s) = @_; return (($s->{"type"} eq "error")); }, {"rules" => $bad});
        $check->((($e->{"code"} eq "bad_rules")), "Invalid team palette rejected atomically");
        $r = $op->($host, "rules", undef, {"rules" => $rules});
        $check->((same($r->{"rules"}->{"teamColors"}, [6, 4, 3, 7])), "Host-selected team palette broadcast");
        $r = $op->($host, "configure", undef, {"target" => $gid, "member" => $member, "colorIndex" => 5});
        $p = ([map { my $p = $_; (($p->{"id"} == $gid)) ? ($p) : () } @{$r->{"players"}}]->[0] // undef);
        $check->(((($p->{"colorIndex"} == 5)) && (($p->{"color"} eq "#ff83bd"))), "Host can recolor remote tank separately from its team");
        $gr = $guest->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "room")) && scalar(grep { $_ } @{[map { my $p = $_; same(($p->{"colorIndex"} // undef), 5) } @{$s->{"players"}}]})); });
        $check->(scalar(grep { $_ } @{[map { my $p = $_; ((($p->{"id"} == $gid)) && (($p->{"color"} eq "#ff83bd"))) } @{$gr->{"players"}}]}), "Guest receives canonical selection, independent of skin");
        $op->($guest, "ready", undef, {"ready" => JSON::PP::true});
        $host->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "room")) && $s->{"canStart"}); });
        $n = scalar(@{$host->{"messages"}});
        $host->send({"type" => "start"});
        $s = $host->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "state")) && (($s->{"phase"} eq "countdown")) && ($s->{"world"} // undef)); }, "after" => $n);
        $check->((((scalar(@{$s->{"pickups"}}) == 4)) && (!grep { !$_ } @{[map { my $p = $_; (($p->{"type"} eq "shield")) } @{$s->{"pickups"}}]})), "Host weapon filter still governs real spawned pickups");
        $tanks = {map { my $p = $_; $p->{"id"} => $p } @{$s->{"tanks"}}};
        $check->(((($tanks->{$gid}->{"color"} eq "#ff83bd")) && (($tanks->{$hello->{"id"}}->{"color"} eq "#75f0cb"))), "Spawn respects tank override and team inherited color");
        $check->((!grep { !$_ } @{[map { my $t = $_; ((($t->{"shieldCharges"} == 0)) && (($t->{"shield"} == 0))) } @{$s->{"tanks"}}]}), "Fresh game has no phantom shield stacks");
        $check->((same($s->{"rules"}->{"teamColors"}, $rules->{"teamColors"})), "State carries authoritative team colors");
        $e = $op->($host, "configure", sub { my ($s) = @_; return (($s->{"type"} eq "error")); }, {"target" => $gid, "member" => $member, "colorIndex" => 2});
        $check->((($e->{"code"} eq "match_active")), "Palette editing locked during active game");
        $s = $host->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "state")) && (($s->{"phase"} eq "playing"))); }, "timeout" => 6);
        $n = scalar(@{$host->{"messages"}});
        $host->send({"type" => "input", "room" => $code, "seq" => 551, "fire" => JSON::PP::true, "power" => "rapid", "shield" => 999, "shieldCharges" => 999, "colorIndex" => 7, "r" => 999});
        $s = $host->wait(sub { my ($s) = @_; return ((($s->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $t = $_; (($t->{"ack"} == 551)) } @{$s->{"tanks"}}]})); }, "after" => $n);
        $tank = ([map { my $t = $_; (($t->{"id"} == $hello->{"id"})) ? ($t) : () } @{$s->{"tanks"}}]->[0] // undef);
        $check->(((($tank->{"power"} eq "")) && (($tank->{"shieldCharges"} == 0)) && (($tank->{"color"} eq "#75f0cb"))), "Inputs cannot grant weapons, shields or colors");
        $check->((!grep { !$_ } @{[map { my $b = $_; (($b->{"owner"} == $hello->{"id"})) ? (((CORE::abs(($b->{"r"} - 3.5)) < 1e-09))) : () } @{$s->{"bullets"}}]}), "Unpowered shots retain normal geometry");
        $host->send({"type" => "input", "room" => $code, "seq" => 552, "fire" => JSON::PP::false});
        $check->((!(exists($s->{"machineBullets"}))), "Compact stream omitted when no machine gun is equipped");
        $report = {"version" => "4.4.0", "passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "Production Go HTTP/WebSocket, real sockets; no fixture grants."};
        $output = path($0)->parent->child("results/v4.4/production-protocol.json");
        make_path("" . $output->parent);
        write_text("" . $output, JSON::PP->new->canonical->pretty->encode($report));
        print(join(" ", "TOTAL", scalar(@{$checks})), "\n");
    1;
    };
    my $caught_error = $@;
    for $p (@{$peers}) {
        $p->close();
    }
    die $caught_error if $caught_error;
};

eval { $main->() };
my $error = $@;
close_peers();
die $error if $error;
