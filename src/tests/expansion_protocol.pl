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
use Mojo::URL;
use Leqra::Protocol qw(peer connect_socket upgrade_status http_json http_status pause write_text token_hex json_text same close_peers);
$| = 1;
my $BASE = shift(@ARGV) // 'http://localhost:8080';
$BASE =~ s{/+$}{};
my $ORIGIN = URI->new($BASE); $ORIGIN->path(''); $ORIGIN->query(undef); $ORIGIN = "$ORIGIN";
# v2.6 room-name checks over the normal production WebSocket handler.
# Run against a dedicated local server:
#   perl tests/expansion_protocol.pl http://localhost:8080
# Requires only the optional `websockets` test package, not a game dependency.

my $main;
$main = sub {
    my ($a, $again, $b, $base, $c, $checks, $err, $first, $guest, $host, $index, $invalid, $joined, $name, $names, $one, $p, $peers, $report, $restored, $resumed, $roster, $suffix, $third, $two, $url);
    $peers = [];
    $checks = [];
    my $check;
    $check = sub {
        my ($condition, $label) = @_;
        die json_text($label) . "\n" unless $condition;
        push(@{$checks}, $label);
        print(join(" ", "PASS", $label), "\n");
    };
    my $new;
    $new = sub {
        my ($p);
        $p = Leqra::Protocol::peer($BASE);
        push(@{$peers}, $p);
        return $p;
    };
    $suffix = token_hex(4);
    eval {
        $names = [("Friday tanks / + &=? #% 🎯 " . $suffix), ("<img src=x onerror=alert(1)> \" " . $suffix), (("💥" x 124) . substr($suffix, 0, 4 - 0))];
        for my $item (@{[map { [$_, $names->[$_]] } 0 .. $#{$names}]}) {
            ($index, $name) = @{$item};
            $host = $new->();
            $host->send({"type" => "create", "code" => (("  " . $name) . "  "), "name" => "HOST"});
            $first = $host->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["welcome", "error"]})); });
            $check->(((($first->{"type"} eq "welcome")) && (($first->{"room"} eq $name)) && $first->{"created"}), ("Custom create preserves text and trims outer spaces (" . $index . ")"));
            $roster = $host->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
            $check->((($roster->{"host"} == $first->{"id"})), ("Custom creator is host (" . $index . ")"));
            $url = Mojo::URL->new($ORIGIN)->path('/')->query({room => $name})->to_string;
            $restored = Mojo::URL->new($url)->query->param('room');
            $guest = $new->();
            $guest->send({"type" => "join", "code" => $restored, "name" => "GUEST"});
            $joined = $guest->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["welcome", "error"]})); });
            $check->(((($joined->{"type"} eq "welcome")) && (($joined->{"room"} eq $name)) && !($joined->{"created"})), ("Encoded invite name joins the original room (" . $index . ")"));
            $roster = $guest->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
            $check->(((($roster->{"host"} == $first->{"id"})) && ((scalar(@{$roster->{"players"}}) == 2))), ("Joining preserves one room and its host (" . $index . ")"));
            $guest->close();
            $host->wait(sub { my ($m) = @_; return ((($m->{"type"} eq "room")) && scalar(grep { $_ } @{[map { my $p = $_; ((($p->{"id"} == $joined->{"id"})) && !($p->{"connected"})) } @{$m->{"players"}}]})); });
            $resumed = $new->();
            $resumed->send({"type" => "join", "code" => $name, "token" => $joined->{"token"}});
            $again = $resumed->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["welcome", "error"]})); });
            $check->(((($again->{"type"} eq "welcome")) && $again->{"resumed"} && (($again->{"id"} == $joined->{"id"}))), ("Custom-name reconnect preserves seat (" . $index . ")"));
        }
        for $name (@{[("x" x 129), "bad\x{0000}name", "​‍", "bad name"]}) {
            $invalid = $new->();
            $invalid->send({"type" => "join", "code" => $name});
            $err = $invalid->wait(sub { my ($m) = @_; return (scalar(grep { same($_, $m->{"type"}) } @{["error", "welcome"]})); });
            $check->(((($err->{"type"} eq "error")) && (($err->{"code"} eq "bad_code"))), ("Invalid single-line/length/visibility input rejected: " . json_text(substr($name, 0, 16 - 0))));
        }
        $base = ("case Room " . $suffix);
        ($one, $two) = @{[$new->(), $new->()]};
        $one->send({"type" => "create", "code" => $base});
        $two->send({"type" => "join", "code" => uc($base)});
        $a = $one->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $b = $two->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $check->(($a->{"created"} && $b->{"created"} && (($a->{"room"} ne $b->{"room"}))), "Custom names are case-sensitive");
        $third = $new->();
        $third->send({"type" => "create", "code" => $base});
        $c = $third->wait(sub { my ($m) = @_; return (($m->{"type"} eq "welcome")); });
        $roster = $third->wait(sub { my ($m) = @_; return (($m->{"type"} eq "room")); });
        $check->((!($c->{"created"}) && (($roster->{"host"} == $a->{"id"}))), "Named Create joins existing room without replacing host");
        $report = {"version" => "3.1.0", "checks_passed" => scalar(@{$checks}), "checks" => $checks, "handler" => "production HTTP/WebSocket handler, loopback TCP; not the browser fixture"};
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
