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
# v3.8 production HTTP/WebSocket integration. No fixture/grant endpoints.

my $main;
$main = sub {
    my ($after, $cap, $checks, $code, $cols, $e, $guest, $host, $label, $n, $name, $output, $p, $peers, $r, $report, $rows, $rules, $s, $seen, $start, $t, $viewer, $vw, $w);
    $checks = [];
    $peers = [];
    my $check;
    $check = sub {
        my ($ok, $s) = @_;
        die json_text($s) . "\n" unless $ok;
        push(@{$checks}, $s);
        print(join(" ", "PASS", $s), "\n");
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
        my ($p, $typ, $predicate) = @_;
        my ($n);
        $predicate //= undef;
        my $kw = $_[3] // {};
        $n = scalar(@{$p->{"messages"}});
        $p->send({"type" => $typ, %{$kw}});
        return $p->wait(($predicate || sub { my ($m) = @_; return (($m->{"type"} eq "room")); }), "after" => $n);
    };
    eval {
        $check->(((http_json(($BASE . "/healthz"))->{"version"} eq "3.8.0")), "Production reports 3.8.0");
        for my $item (@{[["compact", 7, 7, 2, 5], ["standard", 9, 8, 3, 7], ["large", 12, 10, 4, 12], ["huge", 14, 12, 5, 17], ["giant", 16, 14, 6, 23]]}) {
            ($name, $cols, $rows, $start, $cap) = @{$item};
            $host = $peer->();
            $w = $op->($host, "create", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"name" => "HOST"});
            $code = $w->{"room"};
            $r = $host->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
            $check->(((($r->{"rules"}->{"mapSize"} eq "large")) && (scalar(grep { same($_, "scope") } @{$r->{"rules"}->{"weapons"}}))), ($name . ": default large map with Scope available"));
            $guest = $peer->();
            $op->($guest, "join", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"code" => $code, "name" => "GUEST"});
            $viewer = $peer->();
            $vw = $op->($viewer, "join", sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); }, {"code" => $code, "name" => "WATCHER", "spectating" => JSON::PP::true});
            $rules = {%{$r->{"rules"}}};
            %{$rules} = (%{$rules}, "mapSize" => $name, "weapons" => ["scope"], "mode" => "koth", "timeLimit" => 600, "scoreTarget" => 300);
            $e = $op->($guest, "rules", sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, {"rules" => $rules});
            $check->((($e->{"code"} eq "not_host")), ($name . ": guest cannot change map or Scope rules"));
            $r = $op->($host, "rules", undef, {"rules" => $rules});
            $check->(((($r->{"rules"}->{"mapSize"} eq $name)) && (same($r->{"rules"}->{"weapons"}, ["scope"]))), ($name . ": host map/Scope-only settings accepted"));
            $guest->send({"type" => "ready", "ready" => JSON::PP::true});
            $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && $m->{"canStart"}); });
            $n = scalar(@{$host->{"messages"}});
            $host->send({"type" => "start"});
            $s = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "countdown")) && ($m->{"world"} // undef)); }, "after" => $n);
            $check->(((($s->{"world"}->{"cols"} == $cols)) && (($s->{"world"}->{"rows"} == $rows)) && ((scalar(@{$s->{"pickups"}}) == $start))), ($name . ": authoritative map dimensions and starting count"));
            $check->(((!grep { !$_ } @{[map { my $p = $_; (($p->{"type"} eq "scope")) } @{$s->{"pickups"}}]}) && (!grep { !$_ } @{[map { my $t = $_; (($t->{"scopeTime"} == 0)) } @{$s->{"tanks"}}]})), ($name . ": real Scope pickups and unbuffed snapshot timers"));
            for my $item (@{[[$guest, "guest"], [$viewer, "spectator"]]}) {
                ($p, $label) = @{$item};
                $seen = $p->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(keys %{($m->{"world"} // {})}) && (($m->{"phase"} eq "countdown"))); });
                $check->(((same($seen->{"world"}, $s->{"world"})) && (same($seen->{"pickups"}, $s->{"pickups"}))), ((($name . ": ") . $label) . " receives the same map and pickup state"));
            }
            $s = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "playing")) && ((scalar(@{$m->{"pickups"}}) == ($start + 1)))); }, "timeout" => 6);
            $check->(((0.99 <= (600 - $s->{"roundClock"})) && ((600 - $s->{"roundClock"}) <= 1.12)), ($name . ": first extra pickup remains one live second after start"));
            $n = scalar(@{$host->{"messages"}});
            $guest->send({"type" => "input", "seq" => 21, "scopeTime" => 999, "power" => "scope"});
            $after = $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $t = $_; (($t->{"ack"} == 21)) } @{$m->{"tanks"}}]})); }, "after" => $n);
            $check->((!grep { !$_ } @{[map { my $t = $_; ((($t->{"scopeTime"} == 0)) && (($t->{"power"} eq ""))) } @{$after->{"tanks"}}]}), ($name . ": forged scope state is ignored"));
            $e = $op->($host, "rules", sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, {"rules" => $rules});
            $check->((($e->{"code"} eq "match_active")), ($name . ": live match keeps map/rules locked"));
            for $p (@{[$host, $guest, $viewer]}) {
                $p->close();
            }
        }
        $report = {"version" => "3.8.0", "passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "Production server, real WebSockets and ordinary origin validation; no fixture endpoints."};
        $output = path($0)->parent->child("results/scope38-protocol.json");
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
