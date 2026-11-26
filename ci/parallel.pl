#!/usr/bin/env perl
use strict;
use warnings;
use IO::Select;
use POSIX qw(setpgid WNOHANG);

if ( @ARGV == 1 && ( $ARGV[0] eq '-h' || $ARGV[0] eq '--help' ) ) {
    print "Usage: $0 NAME COMMAND [NAME COMMAND ...]\n\n",
      "Run shell commands concurrently, prefixing stdout and stderr with [NAME].\n",
      "Load Fish completions on demand: $0 --fish-completions | source\n";
    exit 0;
}
if ( @ARGV == 1 && $ARGV[0] eq '--fish-completions' ) {
    print "complete -c parallel.pl -s h -l help -d 'Show usage'\n",
      "complete -c parallel.pl -l fish-completions -d 'Print Fish completions'\n";
    exit 0;
}
die "Usage: $0 NAME COMMAND [NAME COMMAND ...]\n" if !@ARGV || @ARGV % 2;

$| = 1;
my ( $interrupted, $forwarded, $status ) = ( 0, 0, 0 );
$SIG{INT}  = sub { $interrupted = 2 };
$SIG{TERM} = sub { $interrupted = 15 };
my $streams = IO::Select->new;
my ( %jobs, %pipes );
while ( @ARGV && !$interrupted ) {
    my ( $name, $command ) = splice @ARGV, 0, 2;
    pipe( my $reader, my $writer ) or die "pipe: $!\n";
    my $pid = fork // die "fork: $!\n";
    if ( !$pid ) {
        setpgid( 0, 0 ) == 0 or die "setpgid: $!\n";
        $SIG{INT} = $SIG{TERM} = 'DEFAULT';
        close $reader;
        open STDOUT, '>&', $writer or die "stdout: $!\n";
        open STDERR, '>&', $writer or die "stderr: $!\n";
        close $writer;
        exec '/bin/sh', '-ec', $command;
        die "exec: $!\n";
    }
    setpgid( $pid, $pid );
    close $writer;
    $jobs{$pid} = {};
    $pipes{ fileno($reader) } = { name => $name, buffer => '', pid => $pid };
    $streams->add($reader);
}

while ( $streams->count || keys %jobs ) {
    if ( $interrupted && !$forwarded ) {
        kill $interrupted, map { -$_ } keys %jobs;
        $forwarded = time;
    }
    if ( $forwarded && time - $forwarded >= 2 ) {
        kill 'KILL', map { -$_ } keys %jobs;
    }
    for my $reader ( $streams->can_read(0.1) ) {
        my $pipe   = $pipes{ fileno($reader) };
        my $length = sysread( $reader, my $chunk, 65536 );
        next if !defined($length) && $!{EINTR};
        die "read: $!\n" unless defined $length;
        $pipe->{buffer} .= $chunk;
        while ( $pipe->{buffer} =~ s/\A(.*?\n)//s ) {
            print "[$pipe->{name}] $1";
        }
        if ( !$length ) {
            print "[$pipe->{name}] $pipe->{buffer}\n" if length $pipe->{buffer};
            $jobs{ $pipe->{pid} }{closed} = 1;
            delete $jobs{ $pipe->{pid} } if $jobs{ $pipe->{pid} }{reaped};
            delete $pipes{ fileno($reader) };
            $streams->remove($reader);
            close $reader;
        }
    }
    for my $pid ( keys %jobs ) {
        next if $jobs{$pid}{reaped};
        next unless waitpid( $pid, WNOHANG ) == $pid;
        $status ||= ( $? & 127 ) ? 128 + ( $? & 127 ) : $? >> 8;
        $jobs{$pid}{reaped} = 1;
        delete $jobs{$pid} if $jobs{$pid}{closed};
    }
}
exit( $interrupted ? 128 + $interrupted : $status );
