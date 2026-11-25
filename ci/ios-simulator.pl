#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use POSIX       qw(SIG_BLOCK SIG_SETMASK SIGINT SIGTERM SIGHUP sigprocmask);
use Time::HiRes qw(time);

my $child;

sub stop {
    my ( $signal, $status ) = @_;
    $SIG{$_} = 'IGNORE' for qw(HUP INT TERM);
    if ( defined $child ) {
        kill $signal, $child;
        waitpid $child, 0;
    }
    exit $status;
}
$SIG{HUP}  = sub { stop( 'HUP',  129 ) };
$SIG{INT}  = sub { stop( 'INT',  130 ) };
$SIG{TERM} = sub { stop( 'TERM', 143 ) };

sub simctl {
    my @arguments = @_;
    my $started   = time;
    print STDERR "Simulator simctl @arguments: started\n";
    my $blocked  = POSIX::SigSet->new( SIGINT, SIGTERM, SIGHUP );
    my $previous = POSIX::SigSet->new;
    sigprocmask( SIG_BLOCK, $blocked, $previous ) or die "sigprocmask: $!\n";
    my $pid = open my $command, '-|';
    defined $pid or die "fork: $!\n";

    if ( !$pid ) {
        $SIG{$_} = 'DEFAULT' for qw(HUP INT TERM);
        sigprocmask( SIG_SETMASK, $previous ) or die "sigprocmask: $!\n";
        exec 'xcrun', 'simctl', @arguments;
        die "xcrun: $!\n";
    }
    $child = $pid;
    sigprocmask( SIG_SETMASK, $previous ) or die "sigprocmask: $!\n";
    my $output = do { local $/; <$command> }
      // '';
    my $success = close $command;
    undef $child;
    printf STDERR "Simulator simctl @arguments: finished in %.1fs\n", time - $started;
    $success or die "simctl @arguments failed\n";
    return $output;
}

my $inventory = decode_json( simctl( 'list', '--json' ) );
my @runtimes  = grep { $_->{identifier} =~ /\.iOS-/ && $_->{isAvailable} } @{ $inventory->{runtimes} };
my @standard =
  grep {
    ( my $version = $_->{version} ) =~ s/\./-/g;
    $_->{identifier} =~ /\.iOS-\Q$version\E\z/
  } @runtimes;
@runtimes = @standard if @standard;
@runtimes = sort {
    my @a          = split /\./, $a->{version};
    my @b          = split /\./, $b->{version};
    my $comparison = 0;
    for my $i ( 0 .. ( @a > @b ? $#a : $#b ) ) {
        $comparison = ( $b[$i] // 0 ) <=> ( $a[$i] // 0 );
        last if $comparison;
    }
    $comparison;
} @runtimes;
for my $runtime (@runtimes) {
    for my $device ( @{ $inventory->{devices}{ $runtime->{identifier} } // [] } ) {
        next unless $device->{name} =~ /^iPhone/ && $device->{isAvailable};
        if ( $device->{state} eq 'Shutdown' ) {
            print STDERR simctl( 'boot', $device->{udid} );
        }
        print STDERR simctl( 'bootstatus', $device->{udid}, '-b' );
        print "$device->{udid}\n";
        exit;
    }
}
die "No available iPhone simulator\n";
