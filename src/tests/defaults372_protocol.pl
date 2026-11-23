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
use Leqra::Protocol
  qw(peer connect_socket upgrade_status http_json http_status pause write_text token_hex json_text same close_peers);
$| = 1;
my $BASE = shift(@ARGV) // 'http://localhost:8080';
$BASE =~ s{/+$}{};
my $ORIGIN = URI->new($BASE);
$ORIGIN->path('');
$ORIGIN->query(undef);
$ORIGIN = "$ORIGIN";

# v3.7.2 live default-frequency/rules tests against the production WebSocket handler.
# Run: perl tests/defaults372_protocol.pl http://127.0.0.1:18772

my $main;
$main = sub {
    my (
        $a,     $b,           $back,    $checks, $clockkey, $e,      $elapsed, $first,
        $guest, $host,        $initial, $last,   $n,        $output, $p,       $peers,
        $prev,  $r,           $rate,    $report, $room,     $rules,  $rw,      $s,
        $token, $transitions, $viewer,  $vw,     $w
    );
    ( $peers, $checks ) = @{ [ [], [] ] };
    my $check;
    $check = sub {
        my ( $ok, $label ) = @_;
        die json_text($label) . "\n" unless $ok;
        push( @{$checks}, $label );
        print( join( " ", "PASS", $label ), "\n" );
    };
    my $peer;
    $peer = sub {
        my ($p);
        $p = Leqra::Protocol::peer($BASE);
        push( @{$peers}, $p );
        return $p;
    };
    my $op;
    $op = sub {
        my ( $p, $typ, $predicate ) = @_;
        my ($n);
        $predicate //= undef;
        my $kw = $_[3] // {};
        $n = scalar( @{ $p->{"messages"} } );
        $p->send( { "type" => $typ, %{$kw} } );
        return $p->wait( ( $predicate || sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } ),
            "after" => $n );
    };
    eval {
        $check->(
            ( ( http_json( ( $BASE . "/healthz" ) )->{"version"} eq "3.7.2" ) ),
            "Production version 3.7.2"
        );
        $host = $peer->();
        $w    = $op->(
            $host, "create",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "name" => "HOST" }
        );
        $room = $host->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
        $check->(
            ( ( $room->{"rules"}->{"pickupRate"} eq "superfast" ) ),
            "Go-created room defaults to Super fast"
        );
        $guest = $peer->();
        $op->(
            $guest, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $w->{"room"}, "name" => "GUEST" }
        );
        $viewer = $peer->();
        $vw     = $op->(
            $viewer, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            {
                "code"       => $w->{"room"},
                "name"       => "WATCHER",
                "spectating" => JSON::PP::true
            }
        );
        $check->( $vw->{"spectating"}, "Watcher keeps spectator role" );

        for $p ( @{ [ $guest, $viewer ] } ) {
            $r = $p->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
            $check->(
                ( ( $r->{"rules"}->{"pickupRate"} eq "superfast" ) ),
                "Joined member receives Super fast rule"
            );
        }
        $rules                 = { %{ $room->{"rules"} } };
        $rules->{"pickupRate"} = "slow";
        $e                     = $op->(
            $guest, "rules",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); },
            { "rules" => $rules }
        );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Guest cannot change spawn frequency" );
        $rules->{"pickupRate"} = "superfast";
        $e = $op->(
            $viewer, "rules",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); },
            { "rules" => $rules }
        );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Spectator cannot change spawn frequency" );

        for $rate ( @{ [ "fast", "superfast" ] } ) {
            $rules->{"pickupRate"} = $rate;
            $r = $op->( $host, "rules", undef, { "rules" => $rules } );
            $check->(
                ( ( $r->{"rules"}->{"pickupRate"} eq $rate ) ),
                ( ( "Host selects " . $rate ) . " through live socket" )
            );
        }
        $rules->{"pickupRate"} = "invalid";
        $e = $op->(
            $host, "rules",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); },
            { "rules" => $rules }
        );
        $check->( ( ( $e->{"code"} eq "bad_rules" ) ), "Unknown spawn frequency is rejected" );
        $guest->send( { "type" => "ready", "ready" => JSON::PP::true } );
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && $m->{"canStart"} );
            }
        );
        $n = scalar( @{ $host->{"messages"} } );
        $host->send( { "type" => "start" } );
        $initial = $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "countdown" ) ) );
            },
            "after" => $n
        );
        $check->( ( ( scalar( @{ $initial->{"pickups"} } ) == 2 ) ), "Online match begins with two pickups" );
        $rules->{"pickupRate"} = "slow";
        $e = $op->(
            $host, "rules",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); },
            { "rules" => $rules }
        );
        $check->( ( ( $e->{"code"} eq "match_active" ) ), "Frequency remains locked during active match" );
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "playing" ) ) );
            }
        );
        $first = $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( scalar( @{ $m->{"pickups"} } ) == 3 ) ) );
            },
            "timeout" => 4
        );
        $clockkey =
          ( ( exists( $first->{"roundClock"} ) ) ? "roundClock" : "clock" );
        $elapsed = ( 75 - $first->{$clockkey} );
        $check->(
            ( ( 0.99 <= $elapsed ) && ( $elapsed <= 1.12 ) ),
            "First additional online pickup after one simulation second"
        );
        $last = $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( scalar( @{ $m->{"pickups"} } ) == 5 ) ) );
            },
            "timeout" => 5
        );
        for $p ( @{ [ $guest, $viewer ] } ) {
            $s = $p->wait(
                sub {
                    my ($m) = @_;
                    return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"tick"} == $last->{"tick"} ) ) );
                },
                "timeout" => 3
            );
            $check->(
                ( same( $s->{"pickups"}, $last->{"pickups"} ) ),
                "Player/spectator receives identical authoritative pickups"
            );
        }
        $transitions = [];
        $prev        = 2;
        for $s ( @{ $host->{"messages"} } ) {
            if ( ( ( ( $s->{"type"} ne "state" ) ) || ( ( $s->{"phase"} ne "playing" ) ) ) ) {
                next;
            }
            $n = scalar( @{ $s->{"pickups"} } );
            if ( ( ( $n > $prev ) ) ) {
                push( @{$transitions}, ( 75 - $s->{$clockkey} ) );
                $prev = $n;
            }
        }
        $check->( ( ( scalar( @{$transitions} ) == 3 ) ), "Three scheduled additions reach five-pickup cap" );
        $check->(
            (
                !grep { !$_ } @{
                    [
                        map {
                            my ( $a, $b ) = @{$_};
                            ( ( 0.95 <= ( $b - $a ) ) && ( ( $b - $a ) <= 2.08 ) )
                          } @{
                            [
                                map {
                                    my $i = $_;
                                    [ $transitions->[$i], [ @{$transitions}[ 1 .. $#{$transitions} ] ]->[$i] ]
                                } 0 .. min( $#{$transitions},
                                    $#{ [ @{$transitions}[ 1 .. $#{$transitions} ] ] } )
                            ]
                          }
                    ]
                }
            ),
            "Repeated online pickup intervals stay in 1–2s range"
        );
        $token = $vw->{"token"};
        $viewer->close();
        pause(0.12);
        $back = $peer->();
        $rw   = $op->(
            $back, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $w->{"room"}, "token" => $token }
        );
        $r = $back->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
        $check->(
            (
                     $rw->{"resumed"}
                  && $rw->{"spectating"}
                  && ( ( $r->{"rules"}->{"pickupRate"} eq "superfast" ) )
            ),
            "Reconnect preserves spectator role and frequency"
        );
        $report = {
            "version"    => "3.7.2",
            "passed"     => scalar( @{$checks} ),
            "checks"     => $checks,
            "spawnTimes" => $transitions,
            "handler"    =>
              "Unmodified production HTTP/WebSocket handler, local loopback. No grant/map fixture endpoints."
        };
        $output = path($0)->parent->child("results/defaults-protocol-v3.7.2.json");
        make_path( "" . $output->parent );
        write_text( "" . $output, JSON::PP->new->canonical->pretty->encode($report) );
        print( join( " ", "TOTAL", scalar( @{$checks} ) ), "\n" );
        1;
    };
    my $caught_error = $@;
    for $p ( @{$peers} ) {
        $p->close();
    }
    die $caught_error if $caught_error;
};

eval { $main->() };
my $error = $@;
close_peers();
die $error if $error;
