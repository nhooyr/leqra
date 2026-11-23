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

# v3.3 spectators through the production HTTP/WebSocket handler, no fixtures.
# Run perl tests/spectators_protocol.pl http://127.0.0.1:8080.

my $main;
$main = sub {
    my (
        $ar, $blank,   $checks, $code,     $cw,      $e,      $empty,   $er,       $extra,
        $h,  $hi,      $i,      $identity, $m,       $n,      $output,  $overflow, $ow,
        $p,  $payload, $peers,  $r,        $removed, $report, $revoked, $roster,   $rw,
        $s,  $t,       $typ,    $v,        $v2,      $vid,    $vw,      $w
    );
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
    my $op;
    $op = sub {
        my ( $p, $typ, $predicate ) = @_;
        my ($n);
        $predicate //= undef;
        my $args = $_[3] // {};
        $n = scalar( @{ $p->{"messages"} } );
        $p->send( { "type" => $typ, %{$args} } );
        return $p->wait( ( $predicate || sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } ),
            "after" => $n );
    };
    my $error;
    $error = sub {
        my ( $p, $typ ) = @_;
        my $args = $_[2] // {};
        return $op->( $p, $typ, sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); }, { %{$args} } );
    };
    my $watch;
    $watch = sub {
        my ( $code, $name ) = @_;
        my ( $p, $w );
        $p = $peer->();
        $w = $op->(
            $p, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            {
                "code"       => $code,
                "name"       => $name,
                "spectating" => JSON::PP::true
            }
        );
        return [ $p, $w ];
    };
    my $own;
    $own = sub {
        my ( $r, $id ) = @_;
        my ($p);
        return (
            [
                map { my $p = $_; ( ( $p->{"id"} == $id ) ) ? ($p) : () }
                  @{ [ @{ $r->{"players"} }, @{ $r->{"spectators"} } ] }
            ]->[0] // undef
        );
    };
    eval {
        $h      = $peer->();
        $code   = ( ( "Spectators " . token_hex(6) ) . " 💥" );
        $roster = [
            { "kind" => "human", "name" => "HOST",   "team" => 1 },
            { "kind" => "local", "name" => "LOCAL2", "team" => 1 },
            {
                "kind"       => "bot",
                "name"       => "BOT A",
                "team"       => 2,
                "difficulty" => "easy"
            },
            {
                "kind"       => "bot",
                "name"       => "BOT B",
                "team"       => 2,
                "difficulty" => "hard"
            }
        ];
        $w = $op->(
            $h, "publish",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "roster" => $roster }
        );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( scalar( @{ $m->{"players"} } ) == 4 ) ) );
            }
        );
        $check->( $r->{"canStart"}, "Four-seat mixed room starts without remote ready votes" );
        $blank = $peer->();
        $e = $error->( $blank, "join", { "code" => $code, "name" => " ", "spectating" => JSON::PP::true } );
        $check->(
            ( ( $e->{"code"} eq "bad_name" ) ),
            "Watch join requires nonempty accepted callsign at server"
        );
        ( $v, $vw ) = @{ $watch->( $code, "WATCHER" ) };
        $r = $v->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
        $check->(
            (
                     $vw->{"spectating"}
                  && ( ( $vw->{"id"} >= 4 ) )
                  && ( ( scalar( @{ $r->{"players"} } ) == 4 ) )
                  && ( ( scalar( @{ $r->{"spectators"} } ) == 1 ) )
            ),
            "Watcher is separate member outside four combat seats"
        );
        $overflow = $peer->();
        $ow       = $op->(
            $overflow, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "name" => "OVERFLOW" }
        );
        $check->( ( $ow->{"spectating"} && $ow->{"full"} ),
            "Regular full-room join falls back to spectator" );
        $r = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( scalar( @{ $m->{"spectators"} } ) == 2 ) ) );
            }
        );
        $check->( $r->{"canStart"}, "Spectators do not prevent match start or require readiness" );
        $check->(
            (
                !grep { !$_ } @{
                    [
                        map {
                            my $p = $_;
                            ( ( !( exists( $p->{"token"} ) ) ) && ( !( exists( $p->{"Controller"} ) ) ) )
                        } @{ [ @{ $r->{"players"} }, @{ $r->{"spectators"} } ] }
                    ]
                }
            ),
            "Both member lists omit credentials and internal controller pointers"
        );
        for my $item (
            @{
                [
                    [
                        "spectate",
                        {
                            "target"     => 0,
                            "member"     => $r->{"players"}->[0]->{"member"},
                            "spectating" => JSON::PP::true
                        }
                    ],
                    [
                        "swap",
                        {
                            "target"          => 0,
                            "member"          => $r->{"players"}->[0]->{"member"},
                            "spectator"       => $vw->{"id"},
                            "spectatorMember" => $vw->{"member"}
                        }
                    ],
                    [
                        "kick",
                        {
                            "target" => 0,
                            "member" => $r->{"players"}->[0]->{"member"}
                        }
                    ]
                ]
            }
          )
        {
            ( $typ, $payload ) = @{$item};
            $e = $error->( $v, $typ, { %{$payload} } );
            $check->(
                ( scalar( grep { same( $_, $e->{"code"} ) } @{ [ "not_host", "not_owned" ] } ) ),
                ( ( "Spectator cannot forge " . $typ ) . " authority over others" )
            );
        }
        $e = $error->( $v, "spectate", { "spectating" => JSON::PP::false } );
        $check->( ( ( $e->{"code"} eq "no_seat" ) ), "Full-room promotion fails without evicting a tank" );
        $n = scalar( @{ $v->{"messages"} } );
        $h->send( { "type" => "start" } );
        $s = $v->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "playing" ) ) );
            },
            "after"   => $n,
            "timeout" => 9
        );
        $check->(
            (
                ( ( scalar( @{ $s->{"tanks"} } ) == 4 ) ) && !(
                    scalar(
                        grep { $_ } @{
                            [
                                map {
                                    my $t = $_;
                                    ( ( $t->{"id"} == $vw->{"id"} ) )
                                } @{ $s->{"tanks"} }
                            ]
                        }
                    )
                )
            ),
            "Spectator receives live world without a spectator tank"
        );
        $v->send(
            {
                "type"    => "input",
                "seq"     => 1,
                "fire"    => JSON::PP::true,
                "forward" => JSON::PP::true
            }
        );
        $e = $error->( $v, "input", { "player" => 0, "seq" => 2, "fire" => JSON::PP::true } );
        $check->(
            ( ( $e->{"code"} eq "not_owned" ) ),
            "Watcher cannot control a tank through forged gameplay input"
        );
        $n = scalar( @{ $v->{"messages"} } );
        $v->send( { "type" => "rename", "name" => "NEW WATCHER" } );
        $m = $v->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "renamed" ) ); }, "after" => $n );
        $check->( ( ( $m->{"name"} eq "NEW WATCHER" ) ), "Spectator can rename themselves while watching" );
        pause(1.05);
        $r = $op->(
            $h, "swap", undef,
            {
                "target"          => 1,
                "member"          => $r->{"players"}->[1]->{"member"},
                "spectator"       => $vw->{"id"},
                "spectatorMember" => $vw->{"member"}
            }
        );
        $check->(
            (
                     ( ( $own->( $r, 1 )->{"name"} eq "NEW WATCHER" ) )
                  && ( ( $own->( $r, $vw->{"id"} )->{"kind"} eq "local" ) )
            ),
            "Host can exchange viewer with active local player"
        );
        $identity = $v->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "identity" ) ) && !( $m->{"spectating"} ) );
            }
        );
        $check->(
            ( ( ( $identity->{"id"} == 1 ) ) && ( ( $identity->{"member"} == $vw->{"member"} ) ) ),
            "Role identity changes tank slot but not membership"
        );
        $s = $v->wait(
            sub {
                my ($m) = @_;
                return (
                    ( ( $m->{"type"} eq "state" ) ) && scalar(
                        grep { $_ } @{
                            [
                                map {
                                    my $t = $_;
                                    ( ( ( $t->{"id"} == 1 ) ) && ( ( $t->{"name"} eq "NEW WATCHER" ) ) )
                                } @{ $m->{"tanks"} }
                            ]
                        }
                    )
                );
            }
        );
        $check->(
            !(
                (
                    [ map { my $t = $_; ( ( $t->{"id"} == 1 ) ) ? ($t) : () } @{ $s->{"tanks"} } ]->[0]
                    // undef
                )->{"alive"}
            ),
            "Incoming mid-round elimination player waits for next round"
        );
        $r   = $op->( $v, "spectate", undef, { "spectating" => JSON::PP::true } );
        $vid = (
            [
                map {
                    my $p = $_;
                    ( ( $p->{"name"} eq "NEW WATCHER" ) ) ? ( $p->{"id"} ) : ()
                } @{ $r->{"spectators"} }
            ]->[0] // undef
        );
        $check->(
            (
                !(
                    scalar(
                        grep { $_ } @{ [ map { my $p = $_; ( ( $p->{"id"} == 1 ) ) } @{ $r->{"players"} } ] }
                    )
                  )
                && ( ( $vid >= 4 ) )
            ),
            "Active player voluntarily frees tank seat to watch"
        );
        $r = $op->( $v, "spectate", undef, { "spectating" => JSON::PP::false } );
        $check->(
            scalar(
                grep { $_ } @{
                    [
                        map {
                            my $p = $_;
                            ( ( $p->{"name"} eq "NEW WATCHER" ) )
                        } @{ $r->{"players"} }
                    ]
                }
            ),
            "Watcher can join an available tank seat"
        );
        $op->( $v, "spectate", undef, { "spectating" => JSON::PP::true } );
        $r = $op->( $h, "lobby", undef, {} );
        $check->(
            ( ( scalar( @{ $r->{"spectators"} } ) == 3 ) ),
            "Returning entire game to lobby retains watchers including local P2"
        );
        pause(1.05);
        $n = scalar( @{ $v->{"messages"} } );
        $h->send( { "type" => "start" } );
        $s = $v->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "playing" ) ) );
            },
            "after"   => $n,
            "timeout" => 9
        );
        $check->(
            (
                ( ( scalar( @{ $s->{"tanks"} } ) == 3 ) ) && !(
                    scalar(
                        grep { $_ } @{
                            [
                                map {
                                    my $t = $_;
                                    ( ( $t->{"name"} eq "NEW WATCHER" ) )
                                } @{ $s->{"tanks"} }
                            ]
                        }
                    )
                )
            ),
            "New game does not auto-promote previous spectators"
        );
        $r   = $op->( $v, "spectate", undef, { "spectating" => JSON::PP::true } );
        $vid = (
            [
                map {
                    my $p = $_;
                    ( ( $p->{"name"} eq "NEW WATCHER" ) ) ? ( $p->{"id"} ) : ()
                } @{ $r->{"spectators"} }
            ]->[0] // undef
        );
        $v->close();
        pause(0.12);
        $v2 = $peer->();
        $rw = $op->(
            $v2, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "token" => $vw->{"token"} }
        );
        $check->(
            ( $rw->{"resumed"} && $rw->{"spectating"} && ( ( $rw->{"id"} == $vid ) ) ),
            "Reconnect restores watch role despite omitted role hint"
        );
        $r       = $op->( $h, "kick", undef, { "target" => $rw->{"id"}, "member" => $rw->{"member"} } );
        $removed = $v2->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "kicked" ) ); } );
        $check->(
            (
                ( ( $removed->{"room"} eq $code ) ) && !(
                    scalar(
                        grep { $_ } @{
                            [
                                map {
                                    my $p = $_;
                                    ( ( $p->{"id"} == $rw->{"id"} ) )
                                } @{ $r->{"spectators"} }
                            ]
                        }
                    )
                )
            ),
            "Host can kick viewers during play and broadcast removal"
        );
        $revoked = $peer->();
        $e       = $op->(
            $revoked, "join",
            sub {
                my ($m) = @_;
                return ( scalar( grep { same( $_, $m->{"type"} ) } @{ [ "welcome", "kicked", "error" ] } ) );
            },
            { "code" => $code, "token" => $vw->{"token"} }
        );
        $check->(
            ( ( $e->{"type"} eq "kicked" ) ),
            "Revoked watcher reconnect credential cannot bypass kick"
        );
        pause(1.05);
        $r = $op->(
            $h, "swap", undef,
            {
                "target"          => 0,
                "member"          => $w->{"member"},
                "spectator"       => $ow->{"id"},
                "spectatorMember" => $ow->{"member"}
            }
        );
        $hi = $h->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "identity" ) ) && $m->{"spectating"} );
            }
        );
        $check->(
            ( ( ( $r->{"host"} == $hi->{"id"} ) ) && ( ( $own->( $r, 0 )->{"name"} eq "OVERFLOW" ) ) ),
            "Host remains host after swapping their own tank with viewer"
        );
        $r = $op->( $h, "lobby", undef, {} );
        $check->( ( ( $r->{"host"} == $hi->{"id"} ) ), "Watching host can end match and edit room" );
        $e = $error->( $overflow, "lobby", {} );
        $check->(
            ( ( $e->{"code"} eq "not_host" ) ),
            "Former spectator taking host tank does not inherit authority"
        );
        $empty = $peer->();
        $cw    = $op->(
            $empty, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            {
                "code"       => ( "Viewer only " . token_hex(5) ),
                "name"       => "WATCH HOST",
                "spectating" => JSON::PP::true
            }
        );
        $er = $empty->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } );
        $check->(
            (
                     $cw->{"created"}
                  && ( ( $cw->{"id"} == $er->{"host"} ) )
                  && !( scalar( @{ $er->{"players"} } ) )
            ),
            "Missing room watch link can create a watching host"
        );

        for $i ( @{ [ 0 .. 15 - 1 ] } ) {
            $watch->( $cw->{"room"}, ( "V " . $i ) );
        }
        $extra = $peer->();
        $e     = $error->(
            $extra, "join",
            {
                "code"       => $cw->{"room"},
                "name"       => "TOO MANY",
                "spectating" => JSON::PP::true
            }
        );
        $check->(
            ( ( $e->{"code"} eq "room_capacity" ) ),
            "Spectator capacity is enforced with clear separate limit"
        );
        $ar = $op->(
            $extra, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $cw->{"room"}, "name" => "TANK" }
        );
        $check->( !( $ar->{"spectating"} ), "Full gallery does not prevent taking free combat seat" );
        $report = {
            "version"       => "3.3.0",
            "checks_passed" => scalar( @{$checks} ),
            "checks"        => $checks,
            "handler"       => "production HTTP/WebSocket, normal origin validation, no fixtures"
        };
        $output = path($0)->parent->child("results/spectators-protocol-v3.3.json");
        make_path( "" . $output->parent );
        write_text( "" . $output, JSON::PP->new->canonical->pretty->encode($report) );
        print( join( " ", json_text( { "passed" => scalar( @{$checks} ) } ) ), "\n" );
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
