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
# v3.1 naming checks through the production WebSocket handler (no test endpoints).

my $main;
$main = sub {
    my ($ack, $checks, $code, $e, $g, $gn, $h, $h2, $label, $local, $m, $n, $op, $output, $p, $peers, $r, $report, $rr, $s, $s2, $welcome);
    $peers = [];
    $checks = [];
    my $check;
    $check = sub {
        my ($v, $s) = @_;
        die json_text($s) . "\n" unless $v;
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
    eval {
        $h = $peer->();
        $code = ("HUD31 " . token_hex(5));
        $h->send({"type" => "publish", "code" => $code, "roster" => [{"name" => "HOST", "kind" => "human", "team" => 1}, {"name" => "PLAYER 2", "kind" => "local", "team" => 1}]});
        $welcome = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $r = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && ((scalar(@{$m->{"players"}}) == 2))); });
        $local = $r->{"players"}->[1];
        $g = $peer->();
        $g->send({"type" => "join", "code" => $code, "name" => "GUEST"});
        $g->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $g->send({"type" => "ready", "ready" => JSON::PP::true});
        $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && ((scalar(@{$m->{"players"}}) == 3)) && $m->{"canStart"}); });
        $n = scalar(@{$h->{"messages"}});
        $gn = scalar(@{$g->{"messages"}});
        $h->send({"type" => "rename_local", "target" => 1, "member" => $local->{"member"}, "name" => "NOVA"});
        $ack = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "renamed")); }, "after" => $n);
        $check->(((($ack->{"id"} == 1)) && (($ack->{"member"} == $local->{"member"})) && (($ack->{"name"} eq "NOVA"))), "Private secondary rename acknowledgement identifies current member");
        $rr = $g->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && (($m->{"players"}->[1]->{"name"} eq "NOVA"))); }, "after" => $gn);
        $check->(($rr->{"players"}->[2]->{"ready"} && $rr->{"canStart"}), "Local rename broadcasts without clearing guest readiness");
        $check->(!(scalar(grep { $_ } @{[map { my $m = $_; (($m->{"type"} eq "renamed")) } @{[@{$g->{"messages"}}[$gn .. $#{$g->{"messages"}}]]}]})), "Secondary rename acknowledgement is not broadcast to other controllers");
        for my $item (@{[[{"target" => 1, "member" => $local->{"member"}}, "Guest cannot rename another controller local"], [{"target" => 0, "member" => $r->{"players"}->[0]->{"member"}}, "Local rename cannot rename a primary human"]]}) {
            ($op, $label) = @{$item};
            $n = scalar(@{$g->{"messages"}});
            $g->send({"type" => "rename_local", "name" => "FORGED", %{$op}});
            $e = $g->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
            $check->(((($e->{"code"} eq "not_owner")) && (($e->{"action"} eq "rename_local"))), $label);
        }
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "rename_local", "target" => 1, "member" => ($local->{"member"} + 100), "name" => "STALE"});
        $e = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
        $check->((($e->{"code"} eq "player_missing")), "Stale member cannot rename a replacement local seat");
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "rename_local", "target" => 1, "member" => $local->{"member"}, "name" => "<🌟>"});
        $e = $h->wait(sub { my ($m) = @_; return (($m->{"type"} eq "error")); }, "after" => $n);
        $check->((($e->{"code"} eq "bad_name")), "Empty sanitized secondary name rejected");
        pause(1.1);
        $h->send({"type" => "start"});
        $s = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"phase"} eq "playing"))); });
        $n = scalar(@{$h->{"messages"}});
        $h->send({"type" => "rename_local", "target" => 1, "member" => $local->{"member"}, "name" => "雪 FOX"});
        $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "renamed")) && (($m->{"name"} eq "雪 FOX"))); }, "after" => $n);
        $s2 = $h->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "state")) && (($m->{"generation"} == $s->{"generation"})) && scalar(grep { $_ } @{[map { my $t = $_; ((($t->{"id"} == 1)) && (($t->{"name"} eq "雪 FOX"))) } @{$m->{"tanks"}}]})); }, "after" => $n);
        $check->(((($s2->{"round"} == $s->{"round"})) && (same($s2->{"scores"}, $s->{"scores"}))), "Live secondary rename updates authoritative tank without a match restart");
        $h->close();
        pause(0.15);
        $h2 = $peer->();
        $h2->send({"type" => "join", "code" => $code, "token" => $welcome->{"token"}});
        $h2->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "welcome")) && $m->{"resumed"}); });
        $rr = $h2->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
        $check->((($rr->{"players"}->[1]->{"name"} eq "雪 FOX")), "Secondary name survives authenticated controller reconnect");
        $n = scalar(@{$h2->{"messages"}});
        $h2->send({"type" => "rename_local", "target" => 1, "member" => $local->{"member"}, "name" => "RESUMED"});
        $h2->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "renamed")) && (($m->{"name"} eq "RESUMED"))); }, "after" => $n);
        $check->(JSON::PP::true, "Original controller can rename its local pilot after host handoff");
        $check->((($rr->{"host"} == 2)), "Host handoff does not transfer secondary controller ownership");
        $report = {"version" => "3.1.0", "checks_passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "normal production HTTP/WebSocket over loopback TCP"};
        $output = path($0)->parent->child("results/gameplay-protocol-v3.1.json");
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
