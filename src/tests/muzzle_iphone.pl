#!/usr/bin/env perl
# Coordinate the native iPhone muzzle test from its host, outside the XCTest runner.
use v5.34;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Path   qw(make_path);
use File::Spec;
use IO::Select;
use JSON::PP;
use LWP::UserAgent;
use HTTP::Request;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);

my ( $xctestrun, $device, $server, $results_dir, $help );
my $fixture_url = 'http://127.0.0.1:18123';
my $usage =
  "Usage: muzzle_iphone.pl --xctestrun FILE --device ID --server URL --results-dir DIR [--fixture URL]\n";
GetOptions(
    'xctestrun=s'   => \$xctestrun,
    'device=s'      => \$device,
    'server=s'      => \$server,
    'results-dir=s' => \$results_dir,
    'fixture=s'     => \$fixture_url,
    'help|h'        => \$help
) or die $usage;
if ($help) { print $usage; exit; }
die $usage if @ARGV;
die $usage
  unless defined($xctestrun)
  && defined($device)
  && defined($server)
  && defined($results_dir);
make_path($results_dir);
my $bundle = File::Spec->catfile( $results_dir, 'tests.xcresult' );
die "Use a fresh results directory; tests.xcresult already exists.\n"
  if -e $bundle;
$fixture_url =~ s{/$}{};
my $json    = JSON::PP->new->canonical->utf8;
my $http    = LWP::UserAgent->new( timeout => 5 );
my $fixture = sub {
    my ($body) = @_;
    my $request = HTTP::Request->new( POST => "$fixture_url/_fixture/muzzle" );
    $request->header( 'Content-Type' => 'application/json' );
    $request->content( $json->encode($body) );
    my $response = $http->request($request);
    die $response->status_line . "\n" unless $response->is_success;
    return $json->decode( $response->decoded_content );
};
my @command = (
    'xcodebuild', '-xctestrun', $xctestrun, '-destination', "id=$device", '-resultBundlePath', $bundle,
    '-only-testing:leqraUITests/GameUITests/testOnlineMuzzleGhostWallsAndTouchTurning',
    'test-without-building'
);
pipe( my $reader, my $writer ) or die "pipe: $!\n";
my $pid = fork();
die "fork: $!\n" unless defined $pid;
if ( !$pid ) {
    close $reader;
    open STDOUT, '>&', $writer or die $!;
    open STDERR, '>&', $writer or die $!;
    close $writer;
    $ENV{TEST_RUNNER_LEQRA_TEST_SERVER}             = $server;
    $ENV{TEST_RUNNER_LEQRA_MUZZLE_DEVICE_UI}        = '1';
    $ENV{TEST_RUNNER_LEQRA_MUZZLE_HOST_COORDINATED} = '1';
    exec { $command[0] } @command;
    die "xcodebuild: $!\n";
}
close $writer;
$| = 1;
$SIG{INT} = sub { die "Interrupted\n" };
my ( %configurations, @checks, @errors, @failures );
sub failed_check { die bless { message => $_[0] }, 'MuzzleAssertion'; }
my $process_line = sub {
    my ($line) = @_;
    if ( index( $line, 'MUZZLE_HOST ' ) < 0 ) {
        print $line if $line =~ /error:|failed|passed/;
        return;
    }
    my ( undef, $payload ) = split /MUZZLE_HOST /, $line, 2;
    my $body  = $json->decode($payload);
    my $key   = $body->{name} . "\0" . ( $body->{infinity} ? 1 : 0 );
    my $state = $fixture->($body);
    if ( !$body->{read} ) {
        die "Fixture did not find a wall\n" unless exists $state->{wallX};
        $configurations{$key} = { %$body, wallX => $state->{wallX} };
        return;
    }
    my $setup = $configurations{$key}
      or die "Missing fixture setup for $body->{name}\n";
    my $ok = eval {
        if ( $body->{check} eq 'fire' ) {
            my $limit = time + 2;
            while ( $state->{shots} == 0 && time < $limit ) {
                sleep 0.05;
                $state = $fixture->($body);
            }
            failed_check('Native Fire never reached the server')
              unless $state->{shots} > 0;
            if ( $body->{weapon} ne 'cannon' ) {
                for my $bullet ( @{ $state->{bullets} // [] } ) {
                    failed_check('Shot crossed the wall')
                      unless $bullet->{x} <= $setup->{wallX} + 0.1;
                    failed_check('Shot did not reflect from the wall')
                      unless $bullet->{bounces} > 0;
                }
            }
        }
        elsif ( $body->{check} eq 'turn' ) {
            failed_check('Native touch turn never reached the server')
              unless abs( $state->{angle} ) > 0.5;
            failed_check('Native touch assistance was not requested')
              unless $state->{input}{touchAim};
        }
        else {
            failed_check('Unknown host check');
        }
        1;
    };
    if ($ok) {
        push @checks, { %$setup, check => $body->{check}, state => $state };
        my $weapon = $setup->{weapon} || 'normal';
        printf "HOST PASS %d/44 %s infinity=%s weapon=%s ghost=%s gap=%s\n",
          scalar(@checks), $body->{check}, $body->{infinity}, $weapon,
          $setup->{ghost}, $setup->{gap};
    }
    else {
        my $failure = $@;
        die $failure unless ref($failure) eq 'MuzzleAssertion';
        my $error = $failure->{message};
        push @errors, $error;
        push @failures,
          {
            %$setup,
            check => $body->{check},
            state => $state,
            error => $error
          };
        say "HOST FAIL $error";
    }
};
my $exit_code;
my $ok = eval {
    my $log_path = File::Spec->catfile( $results_dir, 'xcodebuild.log' );
    open my $log, '>', $log_path or die "$log_path: $!\n";
    $log->autoflush(1);
    my $select   = IO::Select->new($reader);
    my $deadline = time + 20 * 60;
    my $buffer   = '';
    my $eof;
    while ( time < $deadline ) {
        next unless $select->can_read(1);
        my $count = sysread $reader, my $chunk, 16384;
        die "Read xcodebuild output: $!\n" unless defined $count;
        if ( !$count ) { $eof = 1; last; }
        print {$log} $chunk;
        $buffer .= $chunk;
        $process_line->($1) while $buffer =~ s/\A([^\n]*\n)//;
    }
    die "iPhone test exceeded 20 minutes\n" unless $eof;
    $process_line->($buffer) if length $buffer;
    close $reader;
    close $log or die "$log_path: $!\n";
    my $wait_limit = time + 30;
    while ( waitpid( $pid, WNOHANG ) == 0 ) {
        die "xcodebuild did not exit within 30 seconds\n"
          if time >= $wait_limit;
        sleep 0.05;
    }
    $exit_code = ( $? & 127 ) ? -( $? & 127 ) : $? >> 8;
    1;
};
if ( !$ok ) {
    my $error = $@;
    kill 'TERM', $pid;
    my $limit = time + 5;
    while ( waitpid( $pid, WNOHANG ) == 0 ) {
        if ( time >= $limit ) { kill 'KILL', $pid; waitpid( $pid, 0 ); last; }
        sleep 0.05;
    }
    die $error;
}
my $fires  = grep { $_->{check} eq 'fire' } @checks;
my $turns  = grep { $_->{check} eq 'turn' } @checks;
my $passed = $exit_code == 0 && $fires == 40 && $turns == 4 && !@errors;
my %report = (
    passed               => $passed ? JSON::PP::true : JSON::PP::false,
    xcodebuild_exit_code => $exit_code,
    firing_cases_passed  => $fires,
    turn_cases_passed    => $turns,
    errors               => \@errors,
    failures             => \@failures,
    checks               => \@checks
);
my $report_path = File::Spec->catfile( $results_dir, 'report.json' );
open my $report_file, '>', $report_path or die "$report_path: $!\n";
print {$report_file} $json->pretty->encode( \%report );
close $report_file or die "$report_path: $!\n";
say JSON::PP->new->canonical->utf8->encode(
    {
        map  { $_ => $report{$_} }
        grep { $_ ne 'checks' && $_ ne 'failures' } keys %report
    }
);
exit( $passed ? 0 : 1 );
