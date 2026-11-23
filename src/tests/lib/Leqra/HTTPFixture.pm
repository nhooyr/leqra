package Leqra::HTTPFixture;
use v5.34;
use strict;
use warnings;
use HTTP::Daemon;
use HTTP::Response;
use File::Temp  qw(tempfile);
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

sub new {
    my ( $class, $handler ) = @_;
    my $server = HTTP::Daemon->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        ReuseAddr => 1
    ) or die "Cannot start local HTTP fixture: $!\n";
    my ( $state, $state_file ) = tempfile( 'leqra-http-state-XXXXXX', TMPDIR => 1, UNLINK => 1 );
    print {$state} '0';
    close $state;
    my $owner = $$;
    my $pid   = fork();
    die "Cannot fork local HTTP fixture: $!\n" unless defined $pid;

    if ( !$pid ) {
        $SIG{PIPE} = 'IGNORE';
        $SIG{TERM} = sub { POSIX::_exit(0) };
        while ( my $connection = $server->accept ) {
            $connection->timeout(5);
            my $request = $connection->get_request;
            if ($request) {
                open my $input, '<', $state_file or die "$state_file: $!\n";
                read $input, my $generation, 1;
                close $input;
                my $response = eval { $handler->( $request, 0 + $generation ) };
                if ( !$response ) {
                    warn $@ if $@;
                    $response = HTTP::Response->new( 500, 'Fixture failure' );
                }
                $response->header( 'Connection' => 'close' );
                $connection->send_response($response);
            }
            $connection->close;
        }
        POSIX::_exit(0);
    }
    my $url = $server->url;
    $url =~ s{/$}{};
    close $server;
    return bless {
        pid        => $pid,
        owner      => $owner,
        url        => $url,
        state_file => $state_file
    }, $class;
}
sub url { return $_[0]->{url}; }

sub generation {
    my ( $self, $value ) = @_;
    open my $state, '+<', $self->{state_file}
      or die "$self->{state_file}: $!\n";
    print {$state} $value;
    close $state or die "$self->{state_file}: $!\n";
}

sub stop {
    my ($self) = @_;
    return unless $$ == $self->{owner} && $self->{pid};
    kill 'TERM', $self->{pid};
    my $deadline = time + 5;
    while ( waitpid( $self->{pid}, WNOHANG ) == 0 ) {
        if ( time >= $deadline ) {
            kill 'KILL', $self->{pid};
            waitpid( $self->{pid}, 0 );
            last;
        }
        sleep 0.01;
    }
    delete $self->{pid};
    unlink $self->{state_file};
}

sub DESTROY {
    local ( $?, $@, $! );
    $_[0]->stop;
}
1;
