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
my $BASE = shift(@ARGV) // 'http://127.0.0.1:8080';
$BASE =~ s{/+$}{};
my $ORIGIN = URI->new($BASE);
$ORIGIN->path('');
$ORIGIN->query(undef);
$ORIGIN = "$ORIGIN";

# Focused v4.6 production-protocol regression checks.
# Run a production server, then: perl tests/polish45_protocol.pl http://127.0.0.1:8080

my $checks = [];

my $check;
$check = sub {
    my ( $v, $name ) = @_;
    die json_text($name) . "\n" unless $v;
    push( @{$checks}, $name );
    print( join( " ", "PASS", $name ), "\n" );
};

my $new_peer = sub { Leqra::Protocol::peer($BASE) };

my $main;
$main = sub {
    my (
        $before, $cl,   $code, $e,  $gp, $gp3,   $gt, $guest, $gw,
        $health, $host, $hp,   $hw, $p,  $peers, $r,  $res,   $room,
        $rules,  $s,    $s2,   $t,  $t0, $t1,    $tr
    );
    $health = http_json( ( $BASE . "/healthz" ) );
    $check->( same( ( $health->{"version"} // undef ), "4.6.0" ), "Production server reports v4.6.0" );
    $peers = [];
    eval {
        $host  = $new_peer->();
        $guest = $new_peer->();
        push @{$peers}, @{ [ $host, $guest ] };
        $host->send( { "type" => "create", "name" => "HOST" } );
        $hw = $host->wait(
            sub {
                my ($m) = @_;
                return same( ( $m->{"type"} // undef ), "welcome" );
            }
        );
        $code = $hw->{"room"};
        $guest->send( { "type" => "join", "code" => $code, "name" => "GUEST" } );
        $gw = $guest->wait(
            sub {
                my ($m) = @_;
                return same( ( $m->{"type"} // undef ), "welcome" );
            }
        );
        $room = $guest->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "room" )
                      && ( ( scalar( @{ ( $m->{"players"} // [] ) } ) >= 2 ) ) );
            }
        );
        $gp = (
            [
                map {
                    my $p = $_;
                    ( ( $p->{"id"} == $gw->{"id"} ) )
                      ? ($p)
                      : ()
                } @{ $room->{"players"} }
            ]->[0] // undef
        );
        $hp = (
            [
                map {
                    my $p = $_;
                    ( ( $p->{"id"} == $hw->{"id"} ) )
                      ? ($p)
                      : ()
                } @{ $room->{"players"} }
            ]->[0] // undef
        );
        $before = scalar( @{ $guest->{"messages"} } );
        $guest->send(
            {
                "type"       => "paint",
                "target"     => $gp->{"id"},
                "member"     => $gp->{"member"},
                "colorIndex" => 7
            }
        );
        $r = $guest->wait(
            sub {
                my ($m) = @_;
                return (
                    same( ( $m->{"type"} // undef ), "room" ) && same(
                        (
                            [
                                map {
                                    my $p = $_;
                                    ( ( $p->{"id"} == $gw->{"id"} ) )
                                      ? ( ( $p->{"colorIndex"} // undef ) )
                                      : ()
                                } @{ ( $m->{"players"} // [] ) }
                            ]->[0] // undef
                        ),
                        7
                    )
                );
            },
            "after" => $before
        );
        $check->(
            (
                (
                    (
                        [
                            map {
                                my $p = $_;
                                ( ( $p->{"id"} == $gw->{"id"} ) ) ? ($p) : ()
                            } @{ $r->{"players"} }
                        ]->[0] // undef
                    )->{"colorIndex"} == 7
                )
            ),
            "FFA online player paints own tank"
        );
        $before = scalar( @{ $host->{"messages"} } );
        $host->send(
            {
                "type"       => "paint",
                "target"     => $gp->{"id"},
                "member"     => $gp->{"member"},
                "colorIndex" => 3
            }
        );
        $e = $host->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "error" )
                      && same( ( $m->{"action"} // undef ), "paint" ) );
            },
            "after" => $before
        );
        $check->(
            same( ( $e->{"code"} // undef ), "not_owner" ),
            "FFA host cannot repaint remote online human"
        );
        $before = scalar( @{ $host->{"messages"} } );
        $host->send(
            {
                "type"       => "configure",
                "target"     => $gp->{"id"},
                "member"     => $gp->{"member"},
                "colorIndex" => 2
            }
        );
        $e = $host->wait(
            sub {
                my ($m) = @_;
                return same( ( $m->{"type"} // undef ), "error" );
            },
            "after" => $before
        );
        $check->(
            same( ( $e->{"code"} // undef ), "paint_action" ),
            "configure cannot bypass paint ownership"
        );
        $rules = {
            "mode"           => "elimination",
            "teamMode"       => "teams",
            "teamNames"      => [ "AURORA", "EMBER", "TIDE", "VIOLET" ],
            "teamColors"     => [ 4,        5,       6,      7 ],
            "mapSize"        => "large",
            "scoreTarget"    => 1,
            "timeLimit"      => 30,
            "respawnSeconds" => 3,
            "pickupRate"     => "superfast",
            "weapons"        => [ "rapid", "scatter", "shield", "speed" ]
        };
        $before = scalar( @{ $host->{"messages"} } );
        $host->send( { "type" => "rules", "rules" => $rules } );
        $tr = $host->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "room" )
                      && same( ( ( $m->{"rules"} // {} )->{"teamMode"} // undef ), "teams" ) );
            },
            "after" => $before
        );
        $check->(
            (
                !grep { !$_ } @{
                    [
                        map {
                            my $p = $_;
                            ( !( exists( $p->{"colorIndex"} ) ) )
                        } @{ $tr->{"players"} }
                    ]
                }
            ),
            "Teams clear and omit individual FFA paint metadata"
        );
        $gp3 = (
            [
                map {
                    my $p = $_;
                    ( ( $p->{"id"} == $gw->{"id"} ) )
                      ? ($p)
                      : ()
                } @{ $tr->{"players"} }
            ]->[0] // undef
        );
        $before = scalar( @{ $guest->{"messages"} } );
        $guest->send(
            {
                "type"       => "paint",
                "target"     => $gp3->{"id"},
                "member"     => $gp3->{"member"},
                "colorIndex" => 1
            }
        );
        $e = $guest->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "error" )
                      && same( ( $m->{"action"} // undef ), "paint" ) );
            },
            "after" => $before
        );
        $check->( same( ( $e->{"code"} // undef ), "team_color_locked" ), "Teams reject individual paint" );
        for $cl ( @{ [ $host, $guest ] } ) {
            $cl->send( { "type" => "ready", "ready" => JSON::PP::true } );
        }
        $host->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "room" ) && ( $m->{"canStart"} // undef ) );
            }
        );
        $host->send( { "type" => "start" } );
        $s = $host->wait(
            sub {
                my ($m) = @_;
                return (
                    same( ( $m->{"type"} // undef ), "state" )
                      && (
                        scalar(
                            grep { same( $_, ( $m->{"phase"} // undef ) ) } @{ [ "countdown", "playing" ] }
                        )
                      )
                      && ( ( scalar( @{ ( $m->{"tanks"} // [] ) } ) >= 2 ) )
                );
            }
        );
        $t0 = (
            [
                map {
                    my $t = $_;
                    ( ( $t->{"id"} == $hw->{"id"} ) )
                      ? ($t)
                      : ()
                } @{ $s->{"tanks"} }
            ]->[0] // undef
        );
        $t1 = (
            [
                map {
                    my $t = $_;
                    ( ( $t->{"id"} == $gw->{"id"} ) )
                      ? ($t)
                      : ()
                } @{ $s->{"tanks"} }
            ]->[0] // undef
        );
        $check->(
            ( ( $t0->{"color"} ne $t1->{"color"} ) ),
            "Opposing teams use distinct authoritative colors"
        );
        $check->(
            ( ( ( ( $t0->{"speedStacks"} // 0 ) == 0 ) ) && ( ( ( $t1->{"speedStacks"} // 0 ) == 0 ) ) ),
            "Client starts without forged Speed stacks"
        );
        $before = scalar( @{ $guest->{"messages"} } );
        $guest->send(
            {
                "type"        => "input",
                "seq"         => 1,
                "forward"     => JSON::PP::true,
                "speedStacks" => 5,
                "speedTime"   => 99
            }
        );
        $s2 = $guest->wait(
            sub {
                my ($m) = @_;
                return ( same( ( $m->{"type"} // undef ), "state" )
                      && ( ( ( $m->{"tick"} // 0 ) > ( $s->{"tick"} // 0 ) ) ) );
            },
            "after" => $before
        );
        $gt = (
            [
                map {
                    my $t = $_;
                    ( ( $t->{"id"} == $gw->{"id"} ) )
                      ? ($t)
                      : ()
                } @{ $s2->{"tanks"} }
            ]->[0] // undef
        );
        $check->( ( ( ( $gt->{"speedStacks"} // 0 ) == 0 ) ),
            "Client-forged Speed stack fields are ignored" );
        print(
            join(
                " ",
                JSON::PP->new->canonical->pretty->encode(
                    {
                        "checks_passed" => scalar( @{$checks} ),
                        "checks"        => $checks
                    }
                )
            ),
            "\n"
        );
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
