#!/usr/bin/env perl
use strict;
use warnings;
use Cwd            qw(abs_path);
use File::Basename qw(dirname);
use File::Temp     qw(tempdir tempfile);
use File::Path     qw(make_path);
use File::Copy     qw(copy);
use File::Spec;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Time::HiRes qw(sleep clock_gettime CLOCK_MONOTONIC);
$| = 1;

# Build two disposable simulator apps and verify uninterrupted background music.
my $root = dirname( dirname( abs_path(__FILE__) ) );
my ( $products, $help, $require_control );
my $audio_source = "$root/ios/leqra/GameAudio.swift";
my $simulator    = 'booted';
GetOptions(
    'products=s'                   => \$products,
    'audio-source=s'               => \$audio_source,
    'simulator=s'                  => \$simulator,
    'require-interruption-control' => \$require_control,
    'help'                         => \$help
  )
  && !@ARGV
  or die
"Usage: test-ios-audio-mixing.pl [--products DIR] [--audio-source FILE] [--simulator ID] [--require-interruption-control]\n";
if ($help) {
    print
"Verify music continuity with two temporary iOS Simulator apps.\nOptions: --products DIR --audio-source FILE --simulator ID --require-interruption-control\n";
    exit;
}
$ENV{DEVELOPER_DIR} = '/Applications/Xcode.app/Contents/Developer'
  unless exists $ENV{DEVELOPER_DIR};
my $work = tempdir( 'leqra-audio-mixing-XXXXXX', TMPDIR => 1, CLEANUP => 1 );

sub capture {
    my ( $command, $output ) = @_;
    my $pid = fork();
    die "fork: $!\n" unless defined $pid;
    if ( !$pid ) {
        open STDOUT, '>',  $output  or die "$output: $!\n";
        open STDERR, '>&', \*STDOUT or die $!;
        exec { $command->[0] } @$command or die "exec $command->[0]: $!\n";
    }
    waitpid( $pid, 0 );
    return $? >> 8;
}

sub run {
    my @command = @_;
    my ( $file, $path ) = tempfile( DIR => $work );
    close $file;
    my $status = capture( \@command, $path );
    open my $input, '<', $path or die $!;
    my $output = do { local $/; <$input> };
    close $input;
    unlink $path;
    die "Command failed ($status): @command\n$output" if $status;
    $output =~ s/^\s+|\s+$//g;
    return $output;
}

sub read_json {
    open my $f, '<', $_[0] or die "$_[0]: $!\n";
    local $/;
    return decode_json(<$f>);
}

sub check {
    my ( $ok, @details ) = @_;
    die join( ' ', map { ref($_) ? encode_json($_) : $_ } @details ) . "\n"
      unless $ok;
}
if ( !defined $products ) {
    my @build = (
        'xcodebuild',                     '-project',
        "$root/ios/leqra.xcodeproj",      '-scheme',
        'leqra',                          '-configuration',
        'Debug',                          '-sdk',
        'iphonesimulator',                '-destination',
        'generic/platform=iOS Simulator', '-derivedDataPath',
        "$work/build",                    'CODE_SIGNING_ALLOWED=NO',
        'build'
    );
    capture( \@build, "$work/build.log" ) == 0
      or die "xcodebuild failed; see $work/build.log\n";
    $products = "$work/build/Build/Products/Debug-iphonesimulator";
}
my $sdk = run( 'xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path' );
$ENV{SDKROOT} = $sdk;
my $architecture = run( 'uname', '-m' );
my $executable   = "$work/AudioMixingFixture";
run(
    'xcrun',       'swiftc',  '-sdk', $sdk, '-target', "$architecture-apple-ios16.0-simulator",
    '-I',          $products, "$products/leqraCore.o", "$root/ios/Tests/AudioMixing/Fixture.swift",
    $audio_source, '-o',      $executable
);
my @identifiers = ( 'com.leqra.test.audio-sentinel', 'com.leqra.test.audio-client' );
my $error;
eval {
    for my $identifier (@identifiers) {
        my $app = "$work/$identifier.app";
        make_path($app);
        copy( $executable, "$app/AudioMixingFixture" ) or die $!;
        chmod 0755, "$app/AudioMixingFixture";
        my $info = {
            CFBundleIdentifier         => $identifier,
            CFBundleExecutable         => 'AudioMixingFixture',
            CFBundleName               => 'Audio mixing test',
            CFBundlePackageType        => 'APPL',
            CFBundleVersion            => '1',
            CFBundleShortVersionString => '1.0',
            MinimumOSVersion           => '16.0',
            UIDeviceFamily             => [ 1, 2 ],
            UILaunchScreen             => {},
            UIApplicationSceneManifest => {
                UIApplicationSupportsMultipleScenes => JSON::PP::false,
                UISceneConfigurations               => {}
            }
        };
        $info->{UIBackgroundModes} = ['audio']
          if $identifier eq $identifiers[0];
        open my $plist, '>', "$app/Info.plist" or die $!;
        print {$plist} encode_json($info);
        close $plist;
        run( 'plutil',   '-convert', 'xml1',    "$app/Info.plist" );
        run( 'codesign', '--force',  '--sign',  '-',        $app );
        run( 'xcrun',    'simctl',   'install', $simulator, $app );
    }
    run( 'xcrun', 'simctl', 'launch', $simulator, $identifiers[0], '--sentinel' );
    my $container        = run( 'xcrun', 'simctl', 'get_app_container', $simulator, $identifiers[0], 'data' );
    my $status_file      = "$container/Documents/status.json";
    my $client_container = run( 'xcrun', 'simctl', 'get_app_container', $simulator, $identifiers[1], 'data' );
    my $status           = sub { read_json($status_file) };
    my $launch           = sub {
        my @flags = @_;
        my $path  = "$client_container/Documents/status.json";
        unlink $path if -e $path;
        run( 'xcrun', 'simctl', 'launch', '--terminate-running-process',
            $simulator, $identifiers[1], @flags );
        my $deadline = clock_gettime(CLOCK_MONOTONIC) + 10;
        sleep .05 while !-e $path && clock_gettime(CLOCK_MONOTONIC) < $deadline;
        check( -e $path, 'client did not report readiness', \@flags );
        return $path;
    };
    my $read_client = sub {
        my $client = read_json( $_[0] );
        check( !exists( $client->{error} ), $client );
        return $client;
    };
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + 10;
    sleep .2
      while !-e $status_file && clock_gettime(CLOCK_MONOTONIC) < $deadline;
    my $initial = $status->();
    check( $initial->{playing} && !exists( $initial->{error} ), $initial );
    for my $case (
        [ 'muted menu', '--muted' ],
        ['unmuted menu'],
        [ 'muted game',       '--muted',       '--game' ],
        [ 'zero-volume game', '--zero-volume', '--game' ],
        [ 'unmuted game',     '--game' ]
      )
    {
        my ( $name, @flags ) = @$case;
        my $before = $status->();
        my $path   = $launch->(@flags);
        sleep 2;
        my $after  = $status->();
        my $client = $read_client->($path);
        if ( $name eq 'unmuted game' ) {
            check( $client->{category} eq 'AVAudioSessionCategoryAmbient' && $client->{mixes}, $client );
            check( $client->{active} && $client->{running}, $name, $client );
        }
        else {
            check( !$client->{active} && !$client->{running}, $name, $client );
        }
        check( $after->{playing},                    $name, $after );
        check( $after->{interruptions} == 0,         $name, $after );
        check( $after->{time} > $before->{time} + 1, $name, $before, $after );
        print "$name: background playback continued without interruption\n";
    }
    for my $case (
        [ 'menu preview',                   '--preview' ],
        [ 'preview followed by gameplay',   '--preview-resume' ],
        [ 'pause followed by resume',       '--pause-resume' ],
        [ 'rapid interruption and resume',  '--rapid-interruption' ],
        [ 'pause during activation',        '--resume-pause' ],
        [ 'mute during activation',         '--resume-mute' ],
        [ 'zero volume during activation',  '--resume-zero-volume' ],
        [ 'interruption during activation', '--activation-interruption' ]
      )
    {
        my ( $name, $flag ) = @$case;
        my $before = $status->();
        my $path   = $launch->($flag);
        sleep 2;
        my $client  = $read_client->($path);
        my $history = $client->{history};
        if ( $flag =~ /\A--(?:preview|preview-resume|pause-resume|rapid-interruption)\z/ ) {
            check( scalar( grep { $_->{active} && $_->{running} } @$history ), $name, $client );
            check( scalar( grep { $_->{active} && $_->{running} && !$_->{hasPendingPreview} } @$history ),
                $name, $client );
            if ( $flag eq '--preview' ) {
                check( scalar( grep { $_->{previewActive} } @$history ), $name, $client );
                check( !$client->{active} && !$client->{running},        $name, $client );
            }
            else {
                check( $client->{active} && $client->{running} && $client->{requestedActive},
                    $name, $client );
                check( $client->{scenarioStage} >= 1, $name, $client );
            }
        }
        else {
            check(
                $client->{canceledWhilePending},             $name,
                'fixture did not cancel pending activation', $client
            );
            check( !$client->{active} && !$client->{running} && !$client->{activationPending},
                $name, $client );
            check( !scalar( grep { $_->{active} || $_->{running} } @$history ), $name, $client );
        }
        my $after = $status->();
        check( $after->{playing} && $after->{interruptions} == 0, $name, $after );
        check( $after->{time} > $before->{time} + 1, $name, $before, $after );
        print "$name: asynchronous lifecycle and background music passed\n";
    }
    run( 'xcrun', 'simctl', 'launch', '--terminate-running-process',
        $simulator, $identifiers[1], '--exclusive' );
    sleep 2;
    my $exclusive = $status->();
    my $detected  = $exclusive->{interruptions} > 0 || !$exclusive->{playing};
    check( $detected, 'this simulator does not model exclusive-session interruption', $exclusive )
      if $require_control;
    print 'exclusive-session control: '
      . (
        $detected
        ? 'interruption detected'
        : 'SKIPPED; this simulator does not model interruption. Verify background music on an iPhone.'
      ) . "\n";
    1;
} or $error = $@;
for my $identifier (@identifiers) {
    capture( [ 'xcrun', 'simctl', 'terminate', $simulator, $identifier ], File::Spec->devnull );
    capture( [ 'xcrun', 'simctl', 'uninstall', $simulator, $identifier ], File::Spec->devnull );
}
die $error if defined $error;
