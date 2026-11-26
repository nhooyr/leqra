use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use File::Glob qw(bsd_glob);

my $parallel = root() . '/ci/parallel.pl';

subtest 'parallel output retains labels and failures' => sub {
    my $result = run_cmd(
        [
            $^X, $parallel,
            first  => q{printf 'stdout\n'; printf 'stderr\n' >&2; exit 17},
            second => q{printf 'last line'}
        ]
    );
    isnt( $result->{code}, 0, 'a failed formatter makes the runner fail' );
    is( $result->{err}, '', 'all formatter output goes to stdout' );
    is_deeply(
        [ sort split /\n/, $result->{out} ],
        [ sort '[first] stdout', '[first] stderr', '[second] last line' ],
        'stdout, stderr, and an unfinished final line all receive their label'
    );
};

for my $flag (qw(-h --help)) {
    my $result = run_cmd( [ $^X, $parallel, $flag ] );
    is( $result->{code}, 0, "$flag succeeds" );
    like( $result->{out}, qr/usage:/i, "$flag prints usage" );
}

subtest 'interruption reaches formatter descendants' => sub {
    my $tmp    = scratch();
    my $worker = write_text(
        "$tmp/worker.pl",
        <<'WORKER'
use strict;
use warnings;
use Time::HiRes qw(sleep);
my $directory = $ENV{FMT_SIGNAL_DIR};
my $supervisor = getppid();
sub mark {
    open my $file, '>', "$directory/$_[0]" or die $!;
    close $file or die $!;
}
$SIG{INT} = $SIG{TERM} = sub { mark("stopped-$$"); exit 0; };
$SIG{ALRM} = sub { exit 0; };
alarm 5;
my $child = fork();
defined $child or die $!;
if (!$child) {
    alarm 5;
    mark('ready');
    sleep 10;
    exit 0;
}
sleep 0.01 until -e "$directory/ready";
mark("parent-$$");
mark("child-$child");
kill 'INT', $supervisor or die $!;
waitpid $child, 0;
WORKER
    );
    my $result = run_cmd( [ $^X, $parallel, stopped => qq{exec "$^X" "$worker"} ],
        env => { %ENV, FMT_SIGNAL_DIR => $tmp } );
    is( $result->{code}, 130, 'interrupted runner returns 130' );
    my @pids = map { /-(\d+)\z/; $1 } ( bsd_glob("$tmp/parent-*"), bsd_glob("$tmp/child-*") );
    is( scalar @pids, 2, 'formatter and its descendant started' );
    ok( -e "$tmp/stopped-$_", "interrupt reached process $_" ) for @pids;
};

subtest 'formatters start together with batched Perl inputs' => sub {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/ci/fmt.sh', "$project/ci/fmt.sh" );
    copy_file( $parallel,             "$project/ci/parallel.pl" );
    write_text( "$project/$_", '' )
      for (
        'one.pl',     'two.pm',            'three.t', 'space name.pl',
        'missing.pl', 'ios/example.swift', 'android/example.kt'
      );
    write_text( "$project/.gitignore", "ignored.pl\n" );
    write_text( "$project/ignored.pl", '' );
    is( run_cmd( [ 'git', 'init', '-q', $project ] )->{code}, 0, 'initialize fixture' );
    is( run_cmd( [ 'git', '-C', $project, 'add', '.' ] )->{code}, 0, 'track fixture inputs' );
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
open my $log, '>>', "$ENV{FMT_STUB_DIR}/events" or die $!;
flock $log, LOCK_EX or die $!;
print {$log} encode_json({name => $name, args => \@ARGV}), "\n";
close $log or die $!;
open my $ready, '>', "$ENV{FMT_STUB_DIR}/$name.ready" or die $!;
close $ready or die $!;
$SIG{ALRM} = sub { print STDERR "formatters did not start concurrently\n"; exit 91; };
alarm 5;
while (1) {
    my @ready = bsd_glob("$ENV{FMT_STUB_DIR}/*.ready");
    last if @ready == 6;
    sleep 0.01;
}
alarm 0;
print "stdout\n";
print STDERR "stderr\n";
STUB
    my $commands = "$tmp/commands";
    write_text( "$commands/$_", "#!$^X\n$stub", 0755 )
      for qw(npx shfmt perltidy swift-format ktfmt gofmt);
    my %env = ( %ENV, PATH => "$commands:$ENV{PATH}", FMT_STUB_DIR => $commands );
    delete @env{qw(CI GITHUB_ACTIONS)};
    my $result = run_cmd( [ '/bin/sh', "$project/ci/fmt.sh" ], cwd => $tmp, env => \%env );
    is( $result->{code}, 0,  'all six formatter jobs complete concurrently' );
    is( $result->{err},  '', 'formatter stderr is merged into labeled stdout' );
    my $events = json_lines("$commands/events");
    is_deeply(
        [ sort map { $_->{name} } @$events ],
        [ sort qw(npx shfmt perltidy swift-format ktfmt gofmt) ],
        'one invocation per formatter'
    );
    my ($perl) = grep { $_->{name} eq 'perltidy' } @$events;
    is_deeply(
        [ @{ $perl->{args} }[ 0 .. 4 ] ],
        [qw(-npro -l=110 -conv -b -bext=/)],
        'Perl formatting options are unchanged'
    );
    is_deeply(
        [ sort @{ $perl->{args} }[ 5 .. $#{ $perl->{args} } ] ],
        [ sort './ci/parallel.pl', './one.pl', './two.pm', './three.t', './space name.pl' ],
        'one batch includes tracked Perl files and skips missing or ignored files'
    );

    for my $name (qw(prettier shfmt perltidy swift-format ktfmt gofmt)) {
        like( $result->{out}, qr/^\[\Q$name\E\] stdout$/m, "$name stdout is labeled" );
        like( $result->{out}, qr/^\[\Q$name\E\] stderr$/m, "$name stderr is labeled" );
    }
};

done_testing;
