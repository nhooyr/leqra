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
# Production handler checks for sharing, virtual seats, teams and ownership.

my $main;
$main = sub {
    my ($c, $checks, $code, $e, $g, $h, $id, $n, $op, $output, $p, $peers, $r, $r2, $r3, $report, $s, $welcome);
    $peers = [];
    $checks = [];
    my $check;
    $check = sub {
        my ($v, $s) = @_;
        die json_text($s) . "\n" unless $v;
        push(@{$checks}, $s);
        print(join(" ", "PASS", $s), "\n");
    };
    my $new;
    $new = sub {
        my ($p);
        $p = Leqra::Protocol::peer($BASE);
        push(@{$peers}, $p);
        return $p;
    };
    eval {
        $h = $new->();
        $code = ("Mixed team " . token_hex(5));
        $h->send({"type" => "publish", "code" => $code, "roster" => [{"name" => "HOST", "kind" => "human", "team" => 1}, {"name" => "P2", "kind" => "local", "team" => 1}, {"name" => "BOT", "kind" => "bot", "difficulty" => "hard", "team" => 2}]});
        $welcome = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $r = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && ((scalar(@{$m->{"players"}}) == 3))); });
        $check->(($welcome->{"created"} && (($r->{"host"} == 0)) && $r->{"canStart"}), "One controller can host a mixed match");
        $check->(((($r->{"players"}->[1]->{"kind"} eq "local")) && (($r->{"players"}->[1]->{"owner"} == 0))), "Local seat has explicit controller owner");
        $check->(((($r->{"players"}->[2]->{"kind"} eq "bot")) && (($r->{"players"}->[2]->{"difficulty"} eq "hard"))), "Server imports chosen bot difficulty");
        $check->((!grep { !$_ } @{[map { my $p = $_; (!(exists($p->{"token"}))) } @{$r->{"players"}}]}), "Roster contains no reconnect credentials");
        $c = $new->();
        $c->send({"type" => "publish", "code" => $code, "roster" => [{"name" => "OTHER", "kind" => "human", "team" => 1}]});
        $e = $c->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); });
        $check->((($e->{"code"} eq "room_exists")), "Share cannot overwrite an existing room");
        $g = $new->();
        $g->send({"type" => "join", "code" => $code, "name" => "GUEST"});
        $g->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        for $op (@{[{"type" => "add", "kind" => "bot", "difficulty" => "easy"}, {"type" => "configure", "target" => 0, "member" => $r->{"players"}->[0]->{"member"}, "team" => 4}, {"type" => "lobby"}]}) {
            $n = scalar(@{$g->{"messages"}});
            $g->send({%{$op}});
            $e = $g->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
            $check->((($e->{"code"} eq "not_host")), ("Guest cannot " . $op->{"type"}));
        }
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "configure", "target" => 2, "member" => $r->{"players"}->[2]->{"member"}, "difficulty" => "easy", "team" => 2});
        $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && (($m->{"players"}->[2]->{"difficulty"} eq "easy"))); }, "after" => $n);
        $g->send({"type" => "ready", "ready" => JSON::PP::true});
        $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && $m->{"canStart"} && ((scalar(@{$m->{"players"}}) == 4))); });
        $h->send({"type" => "start"});
        $s = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "playing"))); });
        $check->(($s->{"tanks"}->[1]->{"alive"} && $s->{"tanks"}->[2]->{"bot"}), "Local and bot seats enter the real simulation");
        $check->(((($s->{"tanks"}->[2]->{"difficulty"} eq "easy")) && (($s->{"tanks"}->[0]->{"team"} == $s->{"tanks"}->[1]->{"team"}) && ($s->{"tanks"}->[1]->{"team"} == 1))), "Host edits take effect in authoritative tanks");
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "input", "seq" => 20, "left" => JSON::PP::true});
        $h->send({"type" => "input", "player" => 1, "seq" => 2, "right" => JSON::PP::true});
        $s = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && scalar(grep { $_ } @{[map { my $t = $_; ((($t->{"id"} == 1)) && (($t->{"ack"} == 2))) } @{$m->{"tanks"}}]})); }, "after" => $n);
        $check->(((($s->{"tanks"}->[0]->{"ack"} == 20)) && (($s->{"tanks"}->[1]->{"ack"} == 2))), "Separate primary and secondary acknowledgements");
        for $id (@{[0, 1, 2]}) {
            $n = scalar(@{$g->{"messages"}});
            $g->send({"type" => "input", "player" => $id, "seq" => 999, "fire" => JSON::PP::true});
            $e = $g->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
            $check->((($e->{"code"} eq "not_owned")), ("Guest cannot forge input for seat " . $id));
        }
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "configure", "target" => 2, "member" => $r->{"players"}->[2]->{"member"}, "team" => 1});
        $e = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
        $check->((($e->{"code"} eq "match_active")), "Teams cannot change mid-round");
        pause(1.1);
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "lobby"});
        $r2 = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && (($m->{"phase"} eq "lobby"))); }, "after" => $n);
        $check->((((scalar(@{$r2->{"players"}}) == 4)) && (!grep { !$_ } @{[map { my $p = $_; (($p->{"score"} == 0)) } @{$r2->{"players"}}]})), "Return to room resets match but retains all seats");
        $h->send({"type" => "leave"});
        $r3 = $g->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && ((scalar(@{$m->{"players"}}) == 2))); });
        $check->(((($r3->{"host"} == 3)) && !(scalar(grep { $_ } @{[map { my $p = $_; (($p->{"kind"} eq "local")) } @{$r3->{"players"}}]}))), "Owner leave cleans secondary and elects human guest");
        $report = {"version" => "3.1.0", "checks_passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "normal production HTTP/WebSocket handler; loopback TCP"};
        $output = path($0)->parent->child("results/unified-protocol-v3.1.json");
        make_path("" . $output->parent);
        write_text("" . $output, JSON::PP->new->canonical->pretty->encode($report));
        print(join(" ", JSON::PP->new->canonical->pretty->encode($report)), "\n");
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
