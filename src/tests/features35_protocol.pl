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

# v3.5: live production handler checks. Run perl tests/features35_protocol.pl http://127.0.0.1:8080.

my $main;
$main = sub {
    my (
        $bad,     $cfg, $checks,     $code,    $e,         $got,    $health, $hist,
        $host,    $i,   $identities, $initial, $k,         $late,   $lw,     $m,
        $msg,     $n,   $oldtoken,   $output,  $outsider,  $ow,     $p,      $peers,
        $players, $pw,  $r,          $raw,     $readyFrom, $report, $resume, $revoked,
        $rules,   $rw,  $s,          $t,       $viewer,    $vw,     $w,      $watching,
        $world,   $ww,  $x
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
        my $kw = $_[3] // {};
        $n = scalar( @{ $p->{"messages"} } );
        $p->send( { "type" => $typ, %{$kw} } );
        return $p->wait( ( $predicate || sub { my ($m) = @_; return ( ( $m->{"type"} eq "room" ) ); } ),
            "after" => $n );
    };
    my $error;
    $error = sub {
        my ( $p, $typ ) = @_;
        my $kw = $_[2] // {};
        return $op->( $p, $typ, sub { my ($m) = @_; return ( ( $m->{"type"} eq "error" ) ); }, { %{$kw} } );
    };
    my $say;
    $say = sub {
        my ( $p, $text ) = @_;
        my $kw = $_[2] // {};
        return $op->(
            $p, "chat",
            sub {
                my ($m) = @_;
                return ( scalar( grep { same( $_, $m->{"type"} ) } @{ [ "chat", "error" ] } ) );
            },
            { "text" => $text, %{$kw} }
        );
    };
    eval {
        $cfg    = http_json( ( $BASE . "/api/config" ) );
        $health = http_json( ( $BASE . "/healthz" ) );
        $check->( ( ( $health->{"version"} eq "3.5.0" ) ), "Production reports version 3.5.0" );
        $check->( ( ( $cfg->{"maxPlayers"} == 8 ) ),       "API advertises eight tank seats" );
        $host = $peer->();
        $w    = $op->(
            $host, "create",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "name" => "HOST" }
        );
        $code       = $w->{"room"};
        $players    = [$host];
        $identities = [$w];

        for $i ( @{ [ 1 .. 8 - 1 ] } ) {
            $p  = $peer->();
            $pw = $op->(
                $p, "join",
                sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
                { "code" => $code, "name" => ( "P" . $i ) }
            );
            push( @{$players},    $p );
            push( @{$identities}, $pw );
            $check->(
                ( ( ( $pw->{"id"} == $i ) ) && !( $pw->{"spectating"} ) ),
                ( ( "Tank seat " . $i ) . " assigned" )
            );
        }
        $check->(
            (
                (
                    scalar(
                        keys %{ { map { $_ => 1 } ( map { my $w = $_; $w->{"token"} } @{$identities} ) } }
                    ) == 8
                )
            ),
            "Eight private reconnect credentials"
        );
        $r = $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && ( ( scalar( @{ $m->{"players"} } ) == 8 ) ) );
            }
        );
        $check->( ( ( $r->{"rules"}->{"mapSize"} eq "large" ) ), "Shared default map 12x10" );
        $viewer = $peer->();
        $vw     = $op->(
            $viewer, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "name" => "VIEWER" }
        );
        $check->(
            ( $vw->{"spectating"} && $vw->{"full"} && ( ( $vw->{"id"} >= 8 ) ) ),
            "Ninth join falls back to watcher"
        );
        $watching = $peer->();
        $ww       = $op->(
            $watching,
            "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            {
                "code"       => $code,
                "name"       => "WATCH LINK",
                "spectating" => JSON::PP::true
            }
        );
        $check->( $ww->{"spectating"}, "Explicit watcher remains spectator" );
        $outsider = $peer->();
        $ow       = $op->(
            $outsider, "create",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "name" => "OUTSIDER" }
        );
        $e = $error->( $players->[7], "start", {} );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Seat seven cannot start as guest" );
        $rules = { %{ $r->{"rules"} } };
        %{$rules} = (
            %{$rules},
            "mapSize"     => "huge",
            "mode"        => "koth",
            "timeLimit"   => 600,
            "scoreTarget" => 300
        );
        $e = $error->( $viewer, "rules", { "rules" => $rules } );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Spectator cannot change rules" );
        $r = $op->( $host, "rules", undef, { "rules" => $rules } );
        $check->( ( ( $r->{"rules"}->{"mapSize"} eq "huge" ) ), "Host can choose 14x12" );
        $readyFrom = scalar( @{ $host->{"messages"} } );

        for $p ( @{ [ @{$players}[ 1 .. $#{$players} ] ] } ) {
            $p->send( { "type" => "ready", "ready" => JSON::PP::true } );
        }
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && $m->{"canStart"} );
            },
            "after" => $readyFrom
        );
        $host->send( { "type" => "start" } );
        $world = $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) )
                      && same( ( ( $m->{"world"} // {} )->{"cols"} // undef ), 14 ) );
            }
        );
        $check->(
            ( ( ( $world->{"world"}->{"rows"} == 12 ) ) && ( ( scalar( @{ $world->{"tanks"} } ) == 8 ) ) ),
            "14x12 authoritative world has eight tanks"
        );
        $initial =
          { map { json_text($_) => 1 }
              ( map { my $t = $_; [ $t->{"x"}, $t->{"y"} ] } @{ $world->{"tanks"} } ) };
        $check->( ( ( scalar( keys %{$initial} ) == 8 ) ), "Eight distinct server spawn positions" );
        for $p ( @{ [ $players->[7], $viewer, $watching ] } ) {
            $s = $p->wait(
                sub {
                    my ($m) = @_;
                    return ( ( ( $m->{"type"} eq "state" ) )
                          && same( ( ( $m->{"world"} // {} )->{"cols"} // undef ), 14 ) );
                }
            );
            $check->( ( same( $s->{"world"}, $world->{"world"} ) ), "High seat/viewer receives same world" );
        }
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "playing" ) ) );
            }
        );
        $n = scalar( @{ $host->{"messages"} } );
        $players->[7]->send(
            {
                "type"  => "input",
                "seq"   => 91,
                "right" => JSON::PP::true,
                "fire"  => JSON::PP::true,
                "x"     => 99999,
                "y"     => (-3)
            }
        );
        $s = $host->wait(
            sub {
                my ($m) = @_;
                return (
                    ( ( $m->{"type"} eq "state" ) ) && scalar(
                        grep { $_ } @{
                            [
                                map {
                                    my $t = $_;
                                    ( ( ( $t->{"id"} == 7 ) ) && ( ( $t->{"ack"} == 91 ) ) )
                                } @{ $m->{"tanks"} }
                            ]
                        }
                    )
                );
            },
            "after" => $n
        );
        $t = ( [ map { my $t = $_; ( ( $t->{"id"} == 7 ) ) ? ($t) : () } @{ $s->{"tanks"} } ]->[0] // undef );
        $check->(
            (
                ( ( 0 < $t->{"x"} ) && ( $t->{"x"} < $world->{"world"}->{"width"} ) ) && ( ( 0 < $t->{"y"} )
                    && ( $t->{"y"} < $world->{"world"}->{"height"} ) )
            ),
            "Top seat accepts controls, ignores forged coordinates"
        );
        $e = $error->( $viewer, "input", { "player" => 7, "seq" => 92, "fire" => JSON::PP::true } );
        $check->( ( ( $e->{"code"} eq "not_owned" ) ), "Spectator cannot drive seat seven" );
        $players->[7]->send( { "type" => "input", "seq" => 92 } );
        $m = $say->(
            $players->[7],
            "Hello room 💥",
            {
                "name"       => "SPOOF",
                "member"     => $w->{"member"},
                "spectating" => JSON::PP::true
            }
        );
        $check->(
            (
                     ( ( $m->{"type"} eq "chat" ) )
                  && ( ( $m->{"message"}->{"name"} eq "P7" ) )
                  && ( ( $m->{"message"}->{"member"} == $identities->[7]->{"member"} ) )
            ),
            "Chat author cannot be spoofed"
        );
        for $p ( @{ [ $host, $players->[1], $viewer, $watching ] } ) {
            $got = $p->wait(
                sub {
                    my ($x) = @_;
                    return ( ( ( $x->{"type"} eq "chat" ) )
                          && ( ( $x->{"message"}->{"text"} eq "Hello room 💥" ) ) );
                }
            );
            $check->( !( $got->{"message"}->{"spectating"} ), "All members receive player role chat" );
        }
        $check->(
            !(
                scalar(
                    grep { $_ }
                      @{ [ map { my $m = $_; ( ( $m->{"type"} eq "chat" ) ) } @{ $outsider->{"messages"} } ] }
                )
            ),
            "No cross-room chat leak"
        );
        $m = $say->( $viewer, "Spectators can chat", {} );
        $check->(
            ( $m->{"message"}->{"spectating"} && ( ( $m->{"message"}->{"name"} eq "VIEWER" ) ) ),
            "Spectator chat is attributed and accepted during play"
        );
        $say->( $watching, "<script>not HTML</script>", {} );
        $m = $say->( $watching, ( "💥" x 280 ), {} );
        $check->(
            ( ( ( $m->{"type"} eq "chat" ) ) && ( ( length( $m->{"message"}->{"text"} ) == 280 ) ) ),
            "280 Unicode codepoints accepted"
        );
        for $bad ( @{ [ "", "​", "x\ny", ( "💥" x 281 ) ] } ) {
            $e = $say->( $outsider, $bad, {} );
            $check->(
                ( ( ( $e->{"type"} eq "error" ) ) && ( ( $e->{"code"} eq "bad_chat" ) ) ),
                ( "Reject invalid chat " . json_text( substr( $bad, 0, 8 - 0 ) ) )
            );
        }
        pause(1.1);
        for $i ( @{ [ 0 .. 4 - 1 ] } ) {
            $m = $say->( $outsider, ( "burst " . $i ), {} );
            $check->( ( ( $m->{"type"} eq "chat" ) ), ( "Initial chat burst " . $i ) );
        }
        $e = $say->( $outsider, "too fast", {} );
        $check->( ( ( $e->{"code"} eq "chat_rate" ) ), "Chat flood is rate limited" );
        pause(1.1);
        $m = $say->( $outsider, "after refill", {} );
        $check->( ( ( $m->{"type"} eq "chat" ) ), "Rate limit recovers without disconnect" );
        pause(1.05);
        $r = $op->( $host, "lobby", undef, {} );
        $check->(
            ( ( ( scalar( @{ $r->{"players"} } ) == 8 ) ) && ( ( scalar( @{ $r->{"spectators"} } ) == 2 ) ) ),
            "Back to lobby preserves expanded lineup and watchers"
        );
        $readyFrom = scalar( @{ $host->{"messages"} } );

        for $p ( @{ [ @{$players}[ 1 .. $#{$players} ] ] } ) {
            $p->send( { "type" => "ready", "ready" => JSON::PP::true } );
        }
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "room" ) ) && $m->{"canStart"} );
            },
            "after" => $readyFrom
        );
        $host->send( { "type" => "start" } );
        $host->wait(
            sub {
                my ($m) = @_;
                return ( ( ( $m->{"type"} eq "state" ) ) && ( ( $m->{"phase"} eq "countdown" ) ) );
            },
            "after" => ( scalar( @{ $host->{"messages"} } ) - 1 )
        );
        $late = $peer->();
        $lw   = $op->(
            $late, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "name" => "LATE" }
        );
        $hist = $late->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "chat_history" ) ); } );
        $check->(
            ( $lw->{"spectating"} && ( ( scalar( @{ $hist->{"messages"} } ) == 4 ) ) ),
            "New spectator receives history across games"
        );
        $check->(
            ( same( [ map { my $m = $_; $m->{"id"} } @{ $hist->{"messages"} } ], [ 1, 2, 3, 4 ] ) ),
            "Chat IDs ordered and room-local"
        );
        $raw = json_text($hist);
        $check->(
            (
                !grep { !$_ } @{
                    [
                        map {
                            my $x = $_;
                            ( !( ( index( $raw, $x->{"token"} ) >= 0 ) ) )
                        } @{$identities}
                    ]
                }
            ),
            "No reconnect credentials in chat history"
        );
        $oldtoken = $vw->{"token"};
        $viewer->close();
        pause(0.15);
        $resume = $peer->();
        $rw     = $op->(
            $resume, "join",
            sub { my ($m) = @_; return ( ( $m->{"type"} eq "welcome" ) ); },
            { "code" => $code, "token" => $oldtoken }
        );
        $hist = $resume->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "chat_history" ) ); } );
        $check->(
            ( $rw->{"resumed"} && $rw->{"spectating"} && ( ( scalar( @{ $hist->{"messages"} } ) == 4 ) ) ),
            "Reconnect restores spectator and chat history"
        );
        pause(1.05);
        $r = $op->( $host, "kick", undef, { "target" => $rw->{"id"}, "member" => $rw->{"member"} } );
        $k = $resume->wait( sub { my ($m) = @_; return ( ( $m->{"type"} eq "kicked" ) ); } );
        $check->( ( ( $k->{"room"} eq $code ) ), "Host can kick a chatting spectator" );
        $revoked = $peer->();
        $x       = $op->(
            $revoked, "join",
            sub {
                my ($m) = @_;
                return ( scalar( grep { same( $_, $m->{"type"} ) } @{ [ "kicked", "welcome", "error" ] } ) );
            },
            { "code" => $code, "token" => $oldtoken }
        );
        $check->( ( ( $x->{"type"} eq "kicked" ) ), "Kicked spectator token cannot rejoin for chat" );
        $r = $op->( $players->[7], "spectate", undef, { "spectating" => JSON::PP::true } );
        $check->(
            (
                ( ( scalar( @{ $r->{"players"} } ) == 7 ) ) && scalar(
                    grep { $_ }
                      @{ [ map { my $m = $_; ( ( $m->{"name"} eq "P7" ) ) } @{ $r->{"spectators"} } ] }
                )
            ),
            "Seat seven can switch to spectating"
        );
        $msg = $say->( $players->[7], "Now watching", {} );
        $check->( $msg->{"message"}->{"spectating"}, "Chat updates role after switching" );
        $e = $error->( $watching, "kick", { "target" => 0, "member" => $w->{"member"} } );
        $check->( ( ( $e->{"code"} eq "not_host" ) ), "Spectator cannot kick chat peers" );
        $check->(
            (
                !grep { !$_ } @{
                    [
                        map {
                            my $s = $_;
                            ( ( $s->{"type"} eq "state" ) )
                              ? ( ( ( scalar( @{ ( $s->{"scores"} // [] ) } ) == 8 ) ) )
                              : ()
                        } @{ $host->{"messages"} }
                    ]
                }
            ),
            "Every state has eight score slots"
        );
        $report = {
            "version" => "3.5.0",
            "passed"  => scalar( @{$checks} ),
            "checks"  => $checks,
            "handler" => "Production HTTP/WebSocket with normal origin validation; no fixture endpoints."
        };
        $output = path($0)->parent->child("results/features35-protocol.json");
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
