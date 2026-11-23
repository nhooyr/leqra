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

# v3.2 host rules/presets/FFA/objective protocol checks through production HTTP.
# Run: perl tests/features32_protocol.pl http://127.0.0.1:8080
# No fixture endpoints are used.

my $main;
$main = sub {
    my ( $checks, $code, $e, $g, $gw, $h, $h2, $m, $maps, $n, $oldtoken,
        $output, $p, $peers, $r, $report, $rogue, $roster, $s, $v, $w, $welcome );
    $peers  = [];
    $checks = [];
    my $check;
    $check = sub {
        my ( $v, $s ) = @_;
        die json_text($s) . "\n" unless $v;
        push( @{$checks}, $s );
        print( join( " ", "PASS", $s ), "\n" );
    };
    my $peer;
    $peer = sub {
        my ($p);
        $p = Leqra::Protocol::peer($BASE);
        push( @{$peers}, $p );
        return $p;
    };
    my $error;
    $error = sub {
        my ($p) = @_;
        my ($n);
        my $op = $_[1] // {};
        $n = scalar( @{ $p->{"messages"} } );
        $p->send( { %{$op} } );
        return $p->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); }, "after" => $n );
    };
    my $rules;
    $rules = sub {
        my $kw = $_[0] // {};
        return (
            !( scalar( keys %{$kw} ) )
            ? {
                "mode"           => "elimination",
                "teamMode"       => "teams",
                "mapSize"        => "compact",
                "scoreTarget"    => 3,
                "timeLimit"      => 40,
                "respawnSeconds" => 2,
                "pickupRate"     => "off",
                "weapons"        => [ "laser", "shield" ],
                %{$kw}
              }
            : { %{ $rules->( {} ) }, %{$kw} }
        );
    };
    $roster = [
        { "kind" => "human", "name" => "HOST", "team" => 1 },
        { "kind" => "local", "name" => "P2",   "team" => 1 },
        {
            "kind"       => "bot",
            "name"       => "RUST",
            "team"       => 2,
            "difficulty" => "easy"
        }
    ];
    eval {
        $h    = $peer->();
        $code = ( "RULES32 " . token_hex(5) );
        $h->send(
            {
                "type"   => "publish",
                "code"   => $code,
                "roster" => $roster,
                "rules"  => $rules->( { "mode" => "ctf" } )
            }
        );
        $welcome = $h->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); } );
        $r       = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( $m->{"rules"}->{"mode"} eq "ctf" ) ) );
            }
        );
        $check->(
            ( ( ( $r->{"rules"}->{"mode"} eq "ctf" ) ) && ( ( $r->{"rules"}->{"mapSize"} eq "compact" ) ) ),
            "Publication imports configured objective rules"
        );
        $g = $peer->();
        $g->send( { "type" => "join", "code" => $code, "name" => "GUEST" } );
        $gw = $g->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); } );
        $r  = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( scalar( @{ $m->{"players"} } ) == 4 ) ) );
            }
        );
        $check->(
            ( ( $r->{"players"}->[ $gw->{"id"} ]->{"team"} == 2 ) ),
            "New online guest balances into existing team rather than third side"
        );
        $e = $error->(
            $g,
            {
                "type"  => "rules",
                "rules" => $rules->( { "teamMode" => "ffa" } )
            }
        );
        $check->(
            ( ( ( $e->{"code"} eq "not_host" ) ) && ( ( $e->{"action"} eq "rules" ) ) ),
            "Non-host cannot enable FFA through forged command"
        );
        $e = $error->(
            $g,
            {
                "type"   => "preset",
                "rules"  => $rules->( {} ),
                "roster" => $roster
            }
        );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Non-host cannot replace lineup using a preset" );
        $e = $error->(
            $h,
            {
                "type"   => "preset",
                "rules"  => $rules->( {} ),
                "roster" => $roster
            }
        );
        $check->( ( ( $e->{"code"} eq "guests_present" ) ), "Host preset cannot evict active remote guests" );
        $g->send( { "type" => "ready", "ready" => JSON::PP::true } );
        $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && $m->{"canStart"} );
            }
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send(
            {
                "type"  => "rules",
                "rules" => $rules->( { "teamMode" => "ffa" } )
            }
        );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( $m->{"rules"}->{"teamMode"} eq "ffa" ) ) );
            },
            "after" => $n
        );
        $check->(
            ( !grep { !$_ } @{ [ map { my $p = $_; ( ( $p->{"team"} == 0 ) ) } @{ $r->{"players"} } ] } ),
            "Host FFA rule clears all seat teams atomically"
        );
        $check->(
            !( $r->{"players"}->[ $gw->{"id"} ]->{"ready"} ),
            "Rule changes clear online guest readiness"
        );
        $s = $r->{"players"}->[1];
        $e = $error->(
            $h,
            {
                "type"   => "configure",
                "target" => $s->{"id"},
                "member" => $s->{"member"},
                "team"   => 3
            }
        );
        $check->(
            ( ( $e->{"code"} eq "teams_locked" ) ),
            "Even host per-seat team edits are locked until FFA is disabled"
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send(
            {
                "type"  => "rules",
                "rules" => $rules->( { "mode" => "ctf", "teamMode" => "ffa" } )
            }
        );
        $e = $h->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); }, "after" => $n );
        $check->( ( ( $e->{"code"} eq "bad_rules" ) ), "CTF cannot run with Free-for-all" );
        $e = $error->(
            $h,
            {
                "type"  => "rules",
                "rules" => $rules->( { "scoreTarget" => 999 } )
            }
        );
        $check->(
            ( ( $e->{"code"} eq "bad_rules" ) ),
            "Server rejects client-supplied rule values beyond bounds"
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send( { "type" => "rules", "rules" => $rules->( { "mode" => "ctf" } ) } );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( $m->{"rules"}->{"mode"} eq "ctf" ) ) );
            },
            "after" => $n
        );
        $check->(
            (
                     ( ( $r->{"players"}->[0]->{"team"} == 1 ) )
                  && ( ( $r->{"players"}->[1]->{"team"} == 1 ) )
                  && ( ( $r->{"players"}->[2]->{"team"} == 2 ) )
                  && ( ( $r->{"players"}->[3]->{"team"} == 2 ) )
            ),
            "Leaving FFA restores two controller-aware teams"
        );
        $g->send( { "type" => "ready", "ready" => JSON::PP::true } );
        $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && $m->{"canStart"} );
            },
            "after" => $n
        );
        pause(1.05);
        $h->send( { "type" => "start" } );
        $s = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "playing" ) ) );
            },
            "timeout" => 9
        );
        $check->(
            (
                     ( ( $s->{"rules"}->{"mode"} eq "ctf" ) )
                  && ( ( scalar( @{ $s->{"objectives"}->{"flags"} } ) == 2 ) )
            ),
            "Production CTF snapshot contains both server-owned flags"
        );
        $maps = [
            map {
                my $m = $_;
                ( ( ( $m->{"type"} eq "state" ) ) && ( $m->{"world"} // undef ) )
                  ? ($m)
                  : ()
            } @{ $h->{"messages"} }
        ];
        $check->(
            (
                     ( ( $maps->[ (-1) ]->{"world"}->{"cols"} == 7 ) )
                  && ( ( $maps->[ (-1) ]->{"world"}->{"rows"} == 7 ) )
            ),
            "Production maze dimensions respect map rule"
        );
        $check->(
            ( ( ( $s->{"roundClock"} <= 40 ) ) && !( scalar( @{ $s->{"pickups"} } ) ) ),
            "Production clock and pickup-off setting applied"
        );
        $e = $error->( $h, { "type" => "rules", "rules" => $rules->( {} ) } );
        $check->( ( ( $e->{"code"} eq "match_active" ) ), "Even host cannot change match rules during play" );
        $rogue = $peer->();
        $rogue->send(
            {
                "type"   => "objective",
                "scores" => [ map { @{ [300] } } 1 .. 4 ],
                "flags"  => [],
                "mode"   => "koth"
            }
        );
        $rogue->wait_closed(3);
        $check->(
            ( ( $rogue->{"close_code"} == 1008 ) ),
            "Client cannot submit objective score or flag state"
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send(
            {
                "type"    => "input",
                "player"  => 0,
                "seq"     => 1,
                "forward" => JSON::PP::true,
                "fire"    => JSON::PP::true,
                "score"   => 999,
                "flags"   => [],
                "rules"   => $rules->( { "mode" => "koth" } )
            }
        );
        pause(0.12);
        $s = $h->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "state" ) ); }, "after" => $n );
        $check->(
            (
                     ( ( $s->{"rules"}->{"mode"} eq "ctf" ) )
                  && ( !grep { !$_ } @{ [ map { my $v = $_; ( ( $v < 3 ) ) } @{ $s->{"scores"} } ] } )
            ),
            "Forged state attached to input is ignored"
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send( { "type" => "lobby" } );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( $m->{"phase"} eq "lobby" ) ) );
            },
            "after" => $n
        );
        $check->( ( ( $r->{"rules"}->{"mode"} eq "ctf" ) ), "End match retains configured rules" );
        $g->send( { "type" => "leave" } );
        $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( scalar( @{ $m->{"players"} } ) == 3 ) ) );
            },
            "after" => $n
        );
        $n = scalar( @{ $h->{"messages"} } );
        $h->send(
            {
                "type"  => "preset",
                "rules" => $rules->(
                    {
                        "mode"        => "koth",
                        "teamMode"    => "ffa",
                        "scoreTarget" => 15,
                        "timeLimit"   => 60
                    }
                ),
                "roster" => $roster
            }
        );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( $m->{"rules"}->{"mode"} eq "koth" ) ) );
            },
            "after" => $n
        );
        $check->(
            (
                ( ( $r->{"host"} == $welcome->{"id"} ) )
                  && ( !grep { !$_ }
                    @{ [ map { my $p = $_; ( ( $p->{"team"} == 0 ) ) } @{ $r->{"players"} } ] } )
            ),
            "Host-only preset atomically loads KOTH/FFA without changing host"
        );
        pause(1.05);
        $h->send( { "type" => "start" } );
        $s = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) )
                      && ( ( $m->{"phase"} eq "playing" ) )
                      && ( ( $m->{"rules"}->{"mode"} eq "koth" ) ) );
            },
            "after"   => $n,
            "timeout" => 9
        );
        $check->(
            ( ( ( $s->{"objectives"}->{"mode"} eq "koth" ) ) && ( ( $s->{"objectives"}->{"radius"} > 0 ) ) ),
            "Production KOTH snapshot includes authoritative hill"
        );
        $oldtoken = $welcome->{"token"};
        $h->close();
        $h2 = $peer->();
        $h2->send( { "type" => "join", "code" => $code, "token" => $oldtoken } );
        $w = $h2->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); } );
        $r = $h2->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
        $check->(
            ( $w->{"resumed"} && ( ( $r->{"rules"}->{"mode"} eq "koth" ) ) ),
            "Reconnect restores objective room and configured rules"
        );
        $report = {
            "version"       => "3.2.0",
            "checks_passed" => scalar( @{$checks} ),
            "checks"        => $checks,
            "handler"       => "production HTTP/WebSocket with normal origin validation; no test fixture"
        };
        $output = path($0)->parent->child("results/features-protocol-v3.2.json");
        make_path( "" . $output->parent );
        write_text( "" . $output, JSON::PP->new->canonical->pretty->encode($report) );
        print( join( " ", JSON::PP->new->canonical->pretty->encode($report) ), "\n" );
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
