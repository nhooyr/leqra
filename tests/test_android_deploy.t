use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;

my $recorder = <<'PERL';
#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use Cwd qw(getcwd);
use File::Basename qw(basename);
use File::Path qw(make_path);
my $command=basename($0);
my $record={command=>$command,args=>\@ARGV,cwd=>getcwd()};
if ($command eq 'fastlane') {
    my ($index)=grep { $ARGV[$_] eq '--metadata_path' } 0..$#ARGV;
    die 'missing metadata path' unless defined $index;
    open my $notes,'<',"$ARGV[$index+1]/en-US/changelogs/default.txt" or die $!;
    $record->{changelog}=do {local $/;<$notes>};
    close $notes or die $!;
    my ($bundle)=grep { $ARGV[$_] eq '--aab' } 0..$#ARGV;
    die 'missing completed app bundle' unless defined $bundle && -f $ARGV[$bundle+1];
}
open my $trace,'>>',$ENV{ANDROID_DEPLOY_TRACE} or die $!;
print {$trace} encode_json($record),"\n";
close $trace or die $!;
exit 29 if $command eq $ENV{ANDROID_DEPLOY_FAIL};
if ($command eq 'gradlew') {
    my $directory=getcwd().'/android/app/build/outputs/bundle/release';
    make_path($directory);
    open my $bundle,'>',"$directory/app-release.aab" or die $!;
    print {$bundle} "mock release bundle\n";
    close $bundle or die $!;
}
print "$ENV{ANDROID_DEPLOY_VERSION}\n" if $command eq 'version.sh';
print $ENV{ANDROID_DEPLOY_RELEASES} if $command eq 'curl';
print "MOCK_UPLOAD_COMPLETED\n" if $command eq 'fastlane';
PERL

sub fixture {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/deploy/android.sh', "$project/deploy/android.sh" );
    write_text( "$project/android/gradlew",    $recorder, 0755 );
    write_text( "$project/scripts/version.sh", $recorder, 0755 );
    write_text( "$tmp/commands/$_",            $recorder, 0755 ) for qw(fastlane curl);
    make_path("$tmp/unrelated directory");
    return ( $tmp, $project );
}

sub invoke {
    my ( $tmp, $project, $arguments, %options ) = @_;
    my %env = (
        %ENV,
        PATH                    => "$tmp/commands:$ENV{PATH}",
        ANDROID_DEPLOY_TRACE    => "$tmp/trace",
        ANDROID_DEPLOY_FAIL     => $options{fail}    // '',
        ANDROID_DEPLOY_VERSION  => $options{version} // 'v0.10.0',
        ANDROID_DEPLOY_RELEASES => $options{releases}
          // '[{"html_url":"https://github.com/nhooyr/leqra/releases/tag/v0.9.4","prerelease":true}]',
    );
    my $result = run_cmd(
        [ 'sh', "$project/deploy/android.sh", @$arguments ],
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

subtest 'default Android deployment builds a local release bundle without uploading' => sub {
    my ( $tmp,    $project ) = fixture();
    my ( $result, $events )  = invoke( $tmp, $project, [] );
    is( $result->{code}, 0, $result->{err} );
    is_deeply( [ map { $_->{command} } @$events ], ['gradlew'], 'only the Gradle wrapper runs' );
    is( $events->[0]{cwd}, $project, 'build runs from repository root' );
    is_deeply( $events->[0]{args}, [ '-p', 'android', ':app:bundleRelease' ], 'release app bundle task' );
    like(
        $result->{out},
        qr{\Q$project/android/app/build/outputs/bundle/release/app-release.aab\E},
        'prints the completed app bundle path'
    );
    unlike( $result->{out}, qr/Uploaded/, 'does not report an upload' );
    ok( !-e "$project/bin/android-play", 'local build does not generate upload metadata' );
};

subtest 'explicit Android upload uses closed testing and the exact application version' => sub {
    for my $version ( 'v0.10.0', 'v0.10.0-dev' ) {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = invoke( $tmp, $project, ['--upload'], version => $version );
        is( $result->{code}, 0, $result->{err} );
        is_deeply(
            [ map { $_->{command} } @$events ],
            [qw(gradlew version.sh curl fastlane)],
            'build completes before upload and version comes from the shared script'
        );
        is( $_->{cwd}, $project, 'commands run from repository root' ) for @$events;
        is_deeply( $events->[0]{args}, [ '-p', 'android', ':app:bundleRelease' ], 'release bundle build' );
        my ($request) = grep { $_->{command} eq 'curl' } @$events;
        is_deeply(
            $request->{args},
            [
                '--fail',       '--silent',
                '--show-error', 'https://api.github.com/repos/nhooyr/leqra/releases?per_page=1'
            ],
            'fetch the newest published release including prereleases'
        );
        my ($upload) = grep { $_->{command} eq 'fastlane' } @$events;
        is( $upload->{args}[0], 'supply', 'Play Store upload command' );
        my %flags = (
            '--aab'                  => "$project/android/app/build/outputs/bundle/release/app-release.aab",
            '--package_name'         => 'com.leqra',
            '--track'                => 'alpha',
            '--release_status'       => 'completed',
            '--version_name'         => $version,
            '--metadata_path'        => "$project/bin/android-play",
            '--skip_upload_apk'      => 'true',
            '--skip_upload_metadata' => 'true',
            '--skip_upload_images'   => 'true',
            '--skip_upload_screenshots' => 'true',
            '--skip_upload_changelogs'  => 'false',
        );
        is( flag( $upload, $_ ), $flags{$_}, $_ ) for sort keys %flags;
        is(
            $upload->{changelog},
            "Release notes: https://github.com/nhooyr/leqra/releases/tag/v0.9.4\n",
            'English release notes point to the exact published prerelease'
        );
        like(
            $result->{out},
qr{Uploaded \Q$version\E to Google Play closed testing \(alpha\)\.\nRelease notes: https://github\.com/nhooyr/leqra/releases/tag/v0\.9\.4\n},
            'successful upload reports its version, closed track and release notes'
        );
        cmp_ok(
            index( $result->{out}, 'MOCK_UPLOAD_COMPLETED' ),
            '<',
            index( $result->{out}, 'Uploaded' ),
            'upload success is reported only after fastlane returns'
        );
    }
};

subtest 'build and upload failures propagate without false success' => sub {
    for my $case ( [ [], 'gradlew' ], [ ['--upload'], 'gradlew' ], [ ['--upload'], 'fastlane' ] ) {
        my ( $arguments, $failure ) = @$case;
        my ( $tmp,       $project ) = fixture();
        my ( $result,    $events )  = invoke( $tmp, $project, $arguments, fail => $failure );
        is( $result->{code},        29,       "$failure exit status is preserved" );
        is( $events->[-1]{command}, $failure, 'no later command after failure' );
        ok( !grep( $_->{command} eq 'fastlane', @$events ), 'failed build cannot upload' )
          if $failure eq 'gradlew';
        unlike( $result->{out}, qr/Uploaded/, 'failure does not report upload success' );
    }
};

subtest 'release lookup failures stop before uploading or reporting success' => sub {
    for my $case (
        { fail     => 'curl' },
        { releases => '[]' },
        { releases => '[{"prerelease":true}]' },
        { releases => 'invalid JSON' }
      )
    {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = invoke( $tmp, $project, ['--upload'], %$case );
        isnt( $result->{code}, 0, 'unavailable release notes fail the upload command' );
        is_deeply(
            [ map { $_->{command} } @$events ],
            [qw(gradlew version.sh curl)],
            'lookup failure prevents fastlane upload'
        );
        unlike( $result->{out}, qr/Uploaded/, 'lookup failure never reports upload success' );
    }
};

subtest 'help and invalid arguments never build or upload' => sub {
    for my $arguments (
        ['--help'], ['-h'], ['--unknown'], ['unexpected'],
        [ '--upload', 'extra' ],
        [ '--help',   'extra' ]
      )
    {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = invoke( $tmp, $project, $arguments );
        if ( @$arguments == 1 && $arguments->[0] =~ /\A(?:--help|-h)\z/ ) {
            is( $result->{code}, 0, 'help succeeds' );
            like( $result->{out}, qr/Usage:/, 'help describes usage' );
        }
        else {
            isnt( $result->{code}, 0, 'invalid invocation fails' );
        }
        is_deeply( $events, [], 'no Gradle, version, release lookup or upload commands' );
        ok( !-e "$project/bin/android-play", 'no upload metadata created' );
    }
};

done_testing;
