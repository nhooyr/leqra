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
# Ghost/Cannon v4.1 production admission, settings, spawn and authority checks.

my $VERSION = ($ENV{"LEQRA_EXPECT_VERSION"} // "4.1.0");

my $main;
$main = sub {
    my ($b, $bad, $checks, $code, $e, $guest, $host, $n, $name, $output, $owned, $p, $path, $peers, $r, $report, $rules, $s, $seen, $t, $v, $viewer, $welcome);
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
        my ($p, $kind, $predicate) = @_;
        my ($n);
        $predicate //= undef;
        my $kw = $_[3] // {};
        $n = scalar(@{$p->{"messages"}});
        $p->send({"type" => $kind, %{$kw}});
        return $p->wait(($predicate || sub { my ($m) = @_; return (($m->{"type"} eq "room")); }), "after" => $n);
    };
    eval {
        $check->(((http_json(($BASE . "/healthz"))->{"version"} eq $VERSION)), ("Production version " . $VERSION));
        for $path (@{["/_fixture/cannon39", "/_fixture/scope38", "/_fixture/phase41", "/_fixture/combat42"]}) {
            my $e = {code => http_status(($BASE . $path))};
            $check->((($e->{"code"} == 404)), (("Production has no " . $path) . " endpoint"));
        }
        $host = $peer->();
        $welcome = $op->($host, "create", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"name" => "HOST"});
        $code = $welcome->{"room"};
        $r = $host->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
        $check->(((scalar(grep { same($_, "cannon") } @{$r->{"rules"}->{"weapons"}})) && (scalar(grep { same($_, "ghost") } @{$r->{"rules"}->{"weapons"}})) && ((scalar(@{$r->{"rules"}->{"weapons"}}) == 10))), "Default rules advertise ten pickups including Ghost and Cannon");
        $guest = $peer->();
        $op->($guest, "join", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"code" => $code, "name" => "GUEST"});
        $viewer = $peer->();
        $v = $op->($viewer, "join", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"code" => $code, "name" => "WATCHER", "spectating" => JSON::PP::true});
        $check->($v->{"spectating"}, "Cannon update retains spectator admission");
        $rules = {%{$r->{"rules"}}};
        %{$rules} = (%{$rules}, "weapons" => ["ghost"], "mode" => "koth", "timeLimit" => 600, "scoreTarget" => 300);
        for my $item (@{[[$guest, "Guest"], [$viewer, "Spectator"]]}) {
            ($p, $name) = @{$item};
            $e = $op->($p, "rules", sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, {"rules" => $rules});
            $check->((($e->{"code"} eq "not_host")), ($name . " cannot enable or disable weapons"));
        }
        $r = $op->($host, "rules", undef, {"rules" => $rules});
        $check->((same($r->{"rules"}->{"weapons"}, ["ghost"])), "Host can select Ghost-only rules");
        $bad = {%{$rules}, "weapons" => ["ghost", "ghost"]};
        $e = $op->($host, "rules", sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, {"rules" => $bad});
        $check->((($e->{"code"} eq "bad_rules")), "Duplicate Ghost rule rejected");
        $guest->send({"type" => "ready", "ready" => JSON::PP::true});
        $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && $m->{"canStart"}); });
        $n = scalar(@{$host->{"messages"}});
        $host->send({"type" => "start"});
        $s = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "countdown")) && ($m->{"world"} // undef)); }, "after" => $n);
        $check->(((($s->{"world"}->{"cols"} == 12)) && (($s->{"world"}->{"rows"} == 10))), "12x10 default remains unchanged");
        $check->((((scalar(@{$s->{"pickups"}}) == 4)) && (!grep { !$_ } @{[map { my $p = $_; (($p->{"type"} eq "ghost")) } @{$s->{"pickups"}}]})), "Four genuine Ghost pickups seeded by server");
        for my $item (@{[[$guest, "Guest"], [$viewer, "Spectator"]]}) {
            ($p, $name) = @{$item};
            $seen = $p->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "countdown")) && ($m->{"world"} // undef)); });
            $check->((same($seen->{"pickups"}, $s->{"pickups"})), ($name . " receives identical authoritative Ghost pickups"));
        }
        $s = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "playing")) && ((scalar(@{$m->{"pickups"}}) == 5))); }, "timeout" => 6);
        $check->(((0.99 <= (600 - $s->{"roundClock"})) && ((600 - $s->{"roundClock"}) <= 1.13)), "Super fast first-second spawn boundary retained");
        $n = scalar(@{$host->{"messages"}});
        $host->send({"type" => "input", "room" => $code, "seq" => 90, "fire" => JSON::PP::true, "power" => "cannon", "ghostTime" => 999, "charges" => 999, "speed" => 999, "r" => 999, "kind" => "cannon"});
        $s = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $t = $_; (($t->{"ack"} == 90)) } @{$m->{"tanks"}}]})); }, "after" => $n);
        $check->(((([map { my $t = $_; (($t->{"id"} == $welcome->{"id"})) ? ($t) : () } @{$s->{"tanks"}}]->[0] // undef)->{"power"} eq "")), "Forged Cannon grant ignored");
        $check->(((([map { my $t = $_; (($t->{"id"} == $welcome->{"id"})) ? ($t) : () } @{$s->{"tanks"}}]->[0] // undef)->{"ghostTime"} == 0)), "Client cannot grant Ghost or wall movement");
        $owned = [map { my $b = $_; (($b->{"owner"} == $welcome->{"id"})) ? ($b) : () } @{$s->{"bullets"}}];
        $check->((scalar(@{$owned}) && (!grep { !$_ } @{[map { my $b = $_; (((($b->{"kind"} // "") eq "")) && (($b->{"r"} == 3.5)) && ((CORE::abs((((($b->{"vx"} ** 2) + ($b->{"vy"} ** 2)) ** 0.5) - 282)) < 0.001))) } @{$owned}]})), "Unpowered pilot fires only genuine normal-speed/size rounds");
        $host->send({"type" => "input", "room" => $code, "seq" => 91, "fire" => JSON::PP::false});
        $e = $op->($host, "rules", sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, {"rules" => $rules});
        $check->((($e->{"code"} eq "match_active")), "Weapon rules stay locked during play");
        $report = {"version" => $VERSION, "passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "Production HTTP/WebSocket handler; no fixture or grants."};
        $output = path($0)->parent->child((("results/phase41-protocol-v" . $VERSION) . ".json"));
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
