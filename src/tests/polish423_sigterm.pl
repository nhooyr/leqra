#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Cwd        qw(getcwd);
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX           qw(WNOHANG);
use Leqra::Protocol qw(connect_socket http_json pause json_text close_peers);

# Historical v4.23 production-handler SIGTERM checks, against the v4.35.0 server.
my $root = "$FindBin::Bin/..";
my @checks;
$| = 1;

sub check {
    my ( $ok, $label ) = @_;
    die "$label\n" unless $ok;
    push @checks, $label;
    print "PASS $label\n";
}
my $socket = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Listen    => 1
) or die $!;
my $port = $socket->sockport;
close $socket;
my $base      = "http://127.0.0.1:$port";
my $temporary = tempdir( 'leqra423-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my $binary    = "$temporary/leqra";
my $cwd       = getcwd();
chdir $root or die "chdir $root: $!\n";
system( 'go', 'build', '-trimpath', '-o', $binary, '.' ) == 0
  or die "go build failed\n";
chdir $cwd or die "chdir $cwd: $!\n";
my $pid = fork();
die "fork: $!\n" unless defined $pid;

if ( !$pid ) {
    chdir $root or die $!;
    open STDOUT, '>',  '/dev/null' or die $!;
    open STDERR, '>&', \*STDOUT    or die $!;
    exec $binary, '-addr', "127.0.0.1:$port";
    die "exec $binary: $!\n";
}
my $reaped = 0;
eval {
    my $healthy = 0;
    for ( 1 .. 80 ) {
        my $health = eval { http_json("$base/healthz") };
        if ( $health && ( $health->{version} // '' ) eq '4.35.0' ) {
            $healthy = 1;
            last;
        }
        pause(.05);
    }
    check( $healthy, 'Compiled production server reports v4.35.0 healthy' );
    my $ws    = connect_socket( $base, timeout => 3, max_size => 1_000_000 );
    my $hello = $ws->recv(3);
    check(
        ( $hello->{type} // '' ) eq 'server_hello'
          && ( $hello->{version}  // '' ) eq '4.35.0'
          && ( $hello->{protocol} // 0 ) == 1,
        'Production WebSocket sends the v4.23 server hello first'
    );
    $ws->send(
        {
            type     => 'client_hello',
            version  => $hello->{version},
            protocol => $hello->{protocol}
        }
    );
    my $welcome = $ws->op( 'create', sub { $_[0]{type} eq 'welcome' }, name => 'SIGTERM TEST' );
    check( $welcome->{room}, 'Version-matched production client can create a room' );
    kill 'TERM', $pid;
    my $shutdown = eval {
        $ws->wait( sub { $_[0]{type} eq 'server_shutdown' }, timeout => 4 );
    };
    check(
        $shutdown && ( $shutdown->{message} // '' ) =~ /shutting down/i,
        'SIGTERM sends server_shutdown before WebSocket teardown'
    );
    my $exit_status;

    for ( 1 .. 120 ) {
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            $exit_status = $?;
            $reaped      = 1;
            last;
        }
        pause(.05);
    }
    check( defined($exit_status) && $exit_status == 0, 'SIGTERM completes graceful server shutdown' );
    1;
};
my $error = $@;
close_peers();
if ( !$reaped ) { kill 'KILL', $pid; waitpid( $pid, 0 ); }
die $error if $error;
print JSON::PP->new->pretty->encode( { passed => scalar(@checks), checks => \@checks } );
