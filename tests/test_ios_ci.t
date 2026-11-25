use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;

my $command = <<'PERL';
#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use Cwd qw(getcwd);
use File::Basename qw(basename);
my $name=basename($0);
my $stage=$name eq 'swift' ? ($ARGV[0] eq 'test' ? 'core' : $ARGV[-2])
    : $name eq 'xcodebuild' ? $ARGV[-1] : $ARGV[1];
sub record {
    my ($operation)=@_;
    open my $trace,'>>',$ENV{IOS_TRACE} or die $!;
    my $line=encode_json({stage=>$operation,args=>\@ARGV,cwd=>getcwd(),pid=>$$,parent=>getppid(),
        screenshots=>$ENV{TEST_RUNNER_LEQRA_UI_SCREENSHOTS}})."\n";
    syswrite($trace,$line)==length($line) or die 'short trace write';
    close $trace or die $!;
}
sub mark {
    my ($name)=@_;
    open my $marker,'>',"$ENV{IOS_MARKERS}/$name" or die $!;
    close $marker or die $!;
}
sub wait_for {
    my ($name)=@_;
    local $SIG{ALRM}=sub { die "timed out waiting for $name\n"; };
    alarm 10;
    select undef,undef,undef,0.01 until -e "$ENV{IOS_MARKERS}/$name";
    alarm 0;
}
$SIG{TERM}=sub { record("$stage-terminated"); exit 143; };
if ($stage eq 'restore') { wait_for('list.started'); }
record($stage);
if ($name eq 'xcrun') {
    mark("$stage.started");
    wait_for('build.completed') if $stage eq $ENV{IOS_BLOCK_STAGE};
}
if ($stage eq 'build-for-testing' && $ENV{IOS_FAIL} eq $stage) {
    wait_for("$ENV{IOS_BLOCK_STAGE}.started");
}
exit 29 if $stage eq $ENV{IOS_FAIL};
mark('core.completed') if $stage eq 'core';
if ($stage eq 'build-for-testing') {
    die 'build preceded shared regression tests' unless -e "$ENV{IOS_MARKERS}/core.completed";
    mark('build.completed');
}
if ($stage eq 'test-without-building') {
    die 'UI regression tests preceded simulator readiness' unless -e "$ENV{IOS_MARKERS}/bootstatus.completed";
}
if ($stage eq 'list') {
    print encode_json({
        runtimes=>[{identifier=>'com.apple.CoreSimulator.SimRuntime.iOS-26-5',version=>'26.5',isAvailable=>JSON::PP::true}],
        devices=>{'com.apple.CoreSimulator.SimRuntime.iOS-26-5'=>[
            {name=>'iPhone regression fixture',udid=>'fixture-iphone',state=>'Shutdown',isAvailable=>JSON::PP::true}
        ]}
    });
}
mark('bootstatus.completed') if $stage eq 'bootstatus';
PERL

sub fixture {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/ci/ios.sh',           "$project/ci/ios.sh" );
    copy_file( root() . '/ci/ios-simulator.pl', "$project/ci/ios-simulator.pl" );
    write_text( "$tmp/commands/$_", $command, 0755 ) for qw(swift xcodebuild xcrun);
    make_path( "$tmp/build temporary", "$tmp/markers", "$tmp/unrelated directory" );
    return ( $tmp, $project );
}

sub run_ci {
    my ( $tmp, $project, %options ) = @_;
    my %env = (
        %ENV,
        PATH            => "$tmp/commands:$ENV{PATH}",
        RUNNER_TEMP     => "$tmp/build temporary",
        IOS_TRACE       => "$tmp/trace",
        IOS_MARKERS     => "$tmp/markers",
        IOS_BLOCK_STAGE => $options{block} // 'list',
        IOS_FAIL        => $options{fail}  // '',
    );
    delete $env{TEST_RUNNER_LEQRA_UI_SCREENSHOTS};
    $env{TEST_RUNNER_LEQRA_UI_SCREENSHOTS} = $options{screenshots} if exists $options{screenshots};
    my $result = run_cmd(
        [ 'sh', "$project/ci/ios.sh" ],
        cwd => "$tmp/unrelated directory",
        env => \%env
    );
    return ( $result, -e "$tmp/trace" ? json_lines("$tmp/trace") : [] );
}

sub flag {
    my ( $event, $name ) = @_;
    my ($index) = grep { $event->{args}[$_] eq $name } 0 .. $#{ $event->{args} };
    return defined($index) ? $event->{args}[ $index + 1 ] : undef;
}

sub stage {
    my ( $events, $name ) = @_;
    return ( grep { $_->{stage} eq $name } @$events )[0];
}

sub remaining_files {
    my ($tmp) = @_;
    opendir my $directory, "$tmp/build temporary" or die $!;
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $directory;
    closedir $directory or die $!;
    return \@names;
}

subtest 'shared regression tests and app compilation overlap simulator startup' => sub {
    my ( $tmp,    $project ) = fixture();
    my ( $result, $events )  = run_ci( $tmp, $project );
    is( $result->{code}, 0, $result->{err} );
    is_deeply(
        [ map { $_->{stage} } @$events ],
        [qw(list restore core build-for-testing boot bootstatus test-without-building save)],
        'compile while discovery is pending, then wait for readiness before UI regression tests'
    );
    is( $_->{cwd}, $project, 'commands run from repository root' ) for @$events;
    my $core = stage( $events, 'core' );
    is( flag( $core, '--configuration' ), 'release', 'shared regression tests use optimized execution' );
    is( flag( $core, '--build-system' ),  'native',  'native incremental build system' );
    is( flag( $core, '--scratch-path' ),  "$tmp/build temporary/leqra-swift", 'shared cache path' );
    my $build = stage( $events, 'build-for-testing' );
    is(
        flag( $build, '-destination' ),
        'generic/platform=iOS Simulator',
        'compilation needs no booted device'
    );
    ok( grep( /^ARCHS=\S+$/,                @{ $build->{args} } ), 'compile the runner architecture' );
    ok( grep( $_ eq 'ONLY_ACTIVE_ARCH=YES', @{ $build->{args} } ), 'avoid a second simulator architecture' );
    my $ui = stage( $events, 'test-without-building' );

    for my $event (@$events) {
        is(
            $event->{screenshots},
            $event->{stage} eq 'test-without-building' ? '0' : undef,
            "$event->{stage} receives the screenshot default only for UI regression tests"
        );
    }
    is( flag( $ui, '-destination' ), 'id=fixture-iphone', 'UI regression tests use the selected simulator' );
    is( flag( $ui, '-parallel-testing-enabled' ), 'NO',   'one simulator regression test session' );
    is(
        flag( $ui, '-resultBundlePath' ),
        "$tmp/build temporary/leqra-ios-tests.xcresult",
        'retain UI regression test results'
    );
    my @selection = grep { /^-only-testing:/ } @{ $ui->{args} };
    is_deeply(
        \@selection,
        [
            map { "-only-testing:leqraUITests/GameUITests/$_" }
              qw(testUnchangedOfflineCallsignResumeKeepsItsBattleWithoutAnAccountKey testDeathNoticeMatchesTankLabelsInPortraitAndLandscape testFireDragAimsInPlaceInBothLayouts)
        ],
        'retain all three UI regression tests'
    );
    is(
        flag( $build, '-derivedDataPath' ),
        flag( $ui,    '-derivedDataPath' ),
        'execute the same compiled app and regression test bundle'
    );
    is(
        stage( $events, 'restore' )->{args}[-1],
        "$tmp/build temporary/leqra-ios-inputs.json",
        'restore manifest'
    );
    is( stage( $events, 'save' )->{args}[-1], "$tmp/build temporary/leqra-ios-inputs.json", 'save manifest' );
    is_deeply( remaining_files($tmp), [], 'temporary simulator identifier is removed' );
};

subtest 'local UI screenshot opt-in is preserved' => sub {
    my ( $tmp,    $project ) = fixture();
    my ( $result, $events )  = run_ci( $tmp, $project, screenshots => '1' );
    is( $result->{code}, 0, $result->{err} );
    is( stage( $events, 'test-without-building' )->{screenshots},
        '1', 'UI regression tests retain the explicit screenshot opt-in' );
};

subtest 'foreground failures cancel and reap simulator startup without saving a cache' => sub {
    for my $case (
        [ 'restore', 'list' ],
        [ 'core',    'list' ],
        map { [ 'build-for-testing', $_ ] } qw(list boot bootstatus)
      )
    {
        my ( $failure, $blocked ) = @$case;
        my ( $tmp,     $project ) = fixture();
        my ( $result,  $events )  = run_ci( $tmp, $project, fail => $failure, block => $blocked );
        is( $result->{code}, 29, "$failure preserves exit status while $blocked is pending" );
        ok( !stage( $events, 'test-without-building' ), 'no UI launch after failure' );
        ok( !stage( $events, 'save' ),                  'failed run cannot refresh cache metadata' );
        my $child = stage( $events, $blocked );
        ok( $child,                                  "$blocked child started" );
        ok( stage( $events, "$blocked-terminated" ), "$blocked child received cancellation" );
        ok( !kill( 0, $child->{pid} ),               'active simctl child was reaped' );
        ok( !kill( 0, $child->{parent} ),            'simulator helper was reaped' );
        is_deeply( remaining_files($tmp), [], 'temporary simulator identifier is removed after failure' );
    }
};

subtest 'simulator and UI failures prevent later stages and cache saves' => sub {
    for my $failure (qw(list boot bootstatus test-without-building)) {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = run_ci( $tmp, $project, fail => $failure );
        isnt( $result->{code}, 0, "$failure fails the CI entrypoint" );
        if ( $failure eq 'test-without-building' ) {
            is( $result->{code}, 29, 'UI regression test failure preserves its exit status' );
            is( stage( $events, $failure )->{screenshots},
                '0', 'disabling optional screenshots does not hide UI regression test failures' );
        }
        ok( !stage( $events, 'save' ),                  'no cache metadata saved after failure' );
        ok( !stage( $events, 'test-without-building' ), 'simulator failure prevents UI launch' )
          unless $failure eq 'test-without-building';
        is_deeply( remaining_files($tmp), [], 'temporary simulator identifier is removed' );
    }
};

done_testing;
