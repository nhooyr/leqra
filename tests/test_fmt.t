use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use File::Glob qw(bsd_glob);

sub fixture {
    my ($mode)  = @_;
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/ci/fmt.sh', "$project/ci/fmt.sh" );
    write_text( "$project/$_", '' )
      for (
        'one.pl',     'two.pm',            'three.t', 'space name.pl',
        'missing.pl', 'ios/example.swift', 'android/example.kt'
      );
    write_text( "$project/.gitignore", "ignored.pl\n" );
    write_text( "$project/ignored.pl", '' );
    die 'git init failed' if run_cmd( [ 'git', 'init', '-q', $project ] )->{code};
    die 'git add failed' if run_cmd( [ 'git', '-C', $project, 'add', '.' ] )->{code};
    unlink "$project/missing.pl" or die $!;
    my $stub = <<'STUB';
use strict;
use warnings;
use File::Basename qw(basename);
use File::Glob qw(bsd_glob);
use Fcntl qw(:flock);
use JSON::PP;
use Time::HiRes qw(sleep);
my $name = basename($0);
my $directory = $ENV{FMT_STUB_DIR};
sub mark {
    open my $file, '>', "$directory/$_[0]" or die $!;
    close $file or die $!;
}
$SIG{ALRM} = sub { die "formatter fixture timed out\n"; };
alarm 8;
$SIG{INT} = 'IGNORE';
$SIG{TERM} = sub { mark("stopped-$$"); exit 0; };
mark("live-$$");
open my $log, '>>', "$directory/events" or die $!;
flock $log, LOCK_EX or die $!;
print {$log} encode_json({name => $name, args => \@ARGV}), "\n";
close $log or die $!;
if ($ENV{FMT_MODE} eq 'interrupt' && $name eq 'npx') {
    my $child = fork // die $!;
    if (!$child) {
        alarm 8;
        mark("live-$$");
        mark('child-ready');
        sleep 10;
        exit 0;
    }
}
mark("$name.ready");
while (1) {
    my @ready = bsd_glob("$directory/*.ready");
    last if @ready == 6;
    sleep 0.01;
}
sleep 10 if $ENV{FMT_MODE} eq 'interrupt';
$| = 1;
print "stdout\n";
print STDERR "stderr\n";
mark("$name.done");
exit($ENV{FMT_MODE} eq 'failure' && $name eq 'shfmt' ? 17 : 0);
STUB
    my $commands = "$tmp/commands";
    write_text( "$commands/$_", "#!$^X\n$stub", 0755 )
      for qw(npx shfmt perltidy swift-format ktfmt gofmt);
    my %env = (
        %ENV,
        PATH           => "$commands:$ENV{PATH}",
        FMT_STUB_DIR   => $commands,
        FMT_MODE       => $mode,
        PARALLEL_SHELL => '/bin/false'
    );
    delete @env{qw(CI GITHUB_ACTIONS)};
    return ( $tmp, $project, $commands, \%env );
}

for my $mode ( 'success', 'failure' ) {
    subtest "formatter integration: $mode" => sub {
        my ( $tmp, $project, $commands, $env ) = fixture($mode);
        my $result = run_cmd( [ '/bin/sh', "$project/ci/fmt.sh" ], cwd => $tmp, env => $env );
        if ( $mode eq 'success' ) {
            is( $result->{code}, 0, 'all formatters succeed' )
              or diag( $result->{out}, $result->{err} );
        }
        else {
            isnt( $result->{code}, 0, 'a formatter failure is reported' );
        }
        is( $result->{err}, '', 'formatter stderr is merged into stdout' );
        my $events = json_lines("$commands/events");
        is_deeply(
            [ sort map { $_->{name} } @$events ],
            [ sort qw(npx shfmt perltidy swift-format ktfmt gofmt) ],
            'all six jobs start together'
        );
        for my $name (qw(npx shfmt perltidy swift-format ktfmt gofmt)) {
            ok( -e "$commands/$name.done", "$name finishes before the script returns" );
            my $label = $name eq 'npx' ? 'prettier' : $name;
            like( $result->{out}, qr/^\[\Q$label\E\]\tstdout$/m, "$label stdout is labeled" );
            like( $result->{out}, qr/^\[\Q$label\E\]\tstderr$/m, "$label stderr is labeled" );
        }
        if ( $mode eq 'success' ) {
            my ($perl) = grep { $_->{name} eq 'perltidy' } @$events;
            is_deeply(
                [ @{ $perl->{args} }[ 0 .. 4 ] ],
                [qw(-npro -l=110 -conv -b -bext=/)],
                'Perl formatting options are unchanged'
            );
            is_deeply(
                [ sort @{ $perl->{args} }[ 5 .. $#{ $perl->{args} } ] ],
                [ sort './one.pl', './two.pm', './three.t', './space name.pl' ],
                'one batch includes Perl files and skips missing or ignored inputs'
            );
        }
    };
}

subtest 'Ctrl+C stops formatter descendants' => sub {
    my ( $tmp, $project, $commands, $env ) = fixture('interrupt');
    my $driver = write_text( "$tmp/interrupt.pl", <<'DRIVER' );
use strict;
use warnings;
use POSIX qw(setpgid);
use File::Glob qw(bsd_glob);
use Time::HiRes qw(sleep);
my $pid = fork // die $!;
if (!$pid) {
    setpgid(0, 0) == 0 or die $!;
    exec '/bin/sh', $ARGV[0];
    die $!;
}
setpgid($pid, $pid);
$SIG{ALRM} = sub { kill 'KILL', -$pid; die "interrupt fixture timed out\n"; };
alarm 10;
while (1) {
    my @ready = bsd_glob("$ENV{FMT_STUB_DIR}/*.ready");
    last if @ready == 6 && -f "$ENV{FMT_STUB_DIR}/child-ready";
    sleep 0.01;
}
kill 'INT', -$pid or die $!;
waitpid $pid, 0;
exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
DRIVER
    my $result = run_cmd( [ $^X, $driver, "$project/ci/fmt.sh" ], cwd => $tmp, env => $env );
    isnt( $result->{code}, 0, 'interruption returns a nonzero status' );
    my @live = bsd_glob("$commands/live-*");
    is( scalar @live, 7, 'all formatters and one descendant started' );
    for my $file (@live) {
        my ($pid) = $file =~ /live-(\d+)$/;
        ok( -e "$commands/stopped-$pid", "process $pid receives termination" );
    }
};

done_testing;
