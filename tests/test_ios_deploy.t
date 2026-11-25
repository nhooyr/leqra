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
my $command=basename($0);
my $operation=$command eq 'xcrun' ? ($ARGV[2] eq 'process' ? $ARGV[3] : $ARGV[2]) : $ARGV[-1];
$operation='archive' if grep { $_ eq 'archive' } @ARGV;
$operation='settings' if grep { $_ eq '-showBuildSettings' } @ARGV;
$operation='export' if grep { $_ eq '-exportArchive' } @ARGV;
my $record={command=>$command,operation=>$operation,args=>\@ARGV,cwd=>getcwd(),developer=>$ENV{DEVELOPER_DIR},path=>$ENV{PATH}};
if ($operation eq 'export') {
    my ($index)=grep { $ARGV[$_] eq '-exportOptionsPlist' } 0..$#ARGV;
    if (defined $index) {
        open my $options,'<',$ARGV[$index+1] or die $!;
        $record->{exportOptions}=do {local $/;<$options>};
    }
}
open my $log,'>>',$ENV{IOS_DEPLOY_TRACE} or die $!;
print {$log} encode_json($record),"\n";
close $log;
exit 29 if $operation eq ($ENV{IOS_DEPLOY_FAIL}//'');
print $ENV{IOS_DEPLOY_SETTINGS} if $operation eq 'settings';
print "MOCK_EXPORT_COMPLETED\n" if $operation eq 'export';
PERL

sub fixture {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/deploy/ios.sh',           "$project/deploy/ios.sh" );
    copy_file( root() . '/deploy/ios-export.plist', "$project/deploy/ios-export.plist" );
    write_text( "$tmp/commands/$_", $recorder, 0755 ) for qw(xcodebuild xcrun);
    make_path("$tmp/unrelated directory");
    return ( $tmp, $project );
}

sub invoke {
    my ( $tmp, $project, $arguments, %options ) = @_;
    my $settings = exists $options{settings} ? $options{settings} : encode_json(
        [
            { target => 'leqraUITests', buildSettings => { DEVELOPMENT_TEAM => 'WRONGTEAM' } },
            { target => 'leqra',        buildSettings => { DEVELOPMENT_TEAM => 'APPTEAM123' } },
        ]
    );
    my %env = (
        %ENV,
        PATH                => "$tmp/commands:$ENV{PATH}",
        IOS_DEPLOY_TRACE    => "$tmp/trace",
        IOS_DEPLOY_FAIL     => $options{fail} // '',
        IOS_DEPLOY_SETTINGS => $settings,
    );
    my $result = run_cmd(
        [ 'sh', "$project/deploy/ios.sh", @$arguments ],
        cwd => "$tmp/unrelated directory",
        env => \%env
    );
    return ( $result, -e "$tmp/trace" ? json_lines("$tmp/trace") : [] );
}

sub flag {
    my ( $event, $name ) = @_;
    my ($index) = grep { $event->{args}[$_] eq $name } 0 .. $#{ $event->{args} };
    return defined $index ? $event->{args}[ $index + 1 ] : undef;
}

subtest 'App Store export and explicit upload use separate destinations without touching a device' => sub {
    for my $mode ( [ '--app-store', 'export' ], [ '--upload', 'upload' ] ) {
        for my $custom ( 0, 1 ) {
            my ( $tmp, $project ) = fixture();
            my $template  = read_text("$project/deploy/ios-export.plist");
            my @arguments = ( $mode->[0], $custom ? ('custom store output') : () );
            my ( $result, $events ) = invoke( $tmp, $project, \@arguments );
            is( $result->{code}, 0, $result->{err} );
            is_deeply(
                [ map { $_->{operation} } @$events ],
                [qw(settings archive export)],
                'only settings, archive and export commands'
            );
            is( $_->{command}, 'xcodebuild', 'no device installation or launch' ) for @$events;
            is( $_->{cwd},     $project,     'runs from repository root' )        for @$events;
            my ( $settings, $archive, $export ) = @$events;
            like( $settings->{path}, qr{\A\Q$tmp/commands\E:}, 'settings retain the caller PATH' );
            like( $archive->{path},  qr{\A\Q$tmp/commands\E:}, 'archive retains the caller PATH' );
            like(
                $export->{path},
                qr{\A/usr/bin:/bin:/usr/sbin:/sbin:},
                'export prefers Apple system utilities'
            );
            is( flag( $settings, '-destination' ), 'generic/platform=iOS', 'settings use the iOS platform' );
            ok( grep( $_ eq '-json', @{ $settings->{args} } ), 'structured build settings' );
            is( flag( $archive, '-configuration' ), 'Release',              'release archive' );
            is( flag( $archive, '-destination' ),   'generic/platform=iOS', 'generic iOS archive' );
            ok( grep( $_ eq 'CODE_SIGNING_ALLOWED=NO', @{ $archive->{args} } ),
                'cloud signing happens during export' );
            my $output = "$project/" . ( $custom ? 'custom store output' : 'bin/ios' );
            is( flag( $archive, '-archivePath' ), "$output/leqra.xcarchive", 'archive output' );
            is( flag( $export, '-archivePath' ), "$output/leqra.xcarchive", 'exports the completed archive' );
            is(
                flag( $export, '-exportPath' ),
                $mode->[1] eq 'export' ? "$output/export" : undef,
                'export path applies only to local export'
            );
            is(
                flag( $export, '-exportOptionsPlist' ),
                "$output/ExportOptions.plist",
                'uses generated export options'
            );
            ok( grep( $_ eq '-allowProvisioningUpdates', @{ $export->{args} } ),
                'export can use the authenticated account' );
            my $plist = $export->{exportOptions};
            like(
                $plist,
                qr{<key>teamID</key>\s*<string>APPTEAM123</string>},
                'uses the app target team, not the first target'
            );
            like(
                $plist,
                qr{<key>method</key>\s*<string>app-store-connect</string>},
                'App Store distribution'
            );
            like(
                $plist,
                qr{<key>destination</key>\s*<string>\Q$mode->[1]\E</string>},
                'requested distribution destination'
            );
            like(
                $plist,
                qr{<key>signingStyle</key>\s*<string>automatic</string>},
                'automatic distribution signing'
            );
            like(
                $plist,
                qr{<key>manageAppVersionAndBuildNumber</key>\s*<false\s*/>},
                'preserves application version and build'
            );
            is( read_text("$project/deploy/ios-export.plist"), $template, 'template is not modified' );
            like(
                $template,
                qr{<key>destination</key>\s*<string>export</string>},
                'static template remains local export'
            );

            if ( $mode->[1] eq 'upload' ) {
                like(
                    $result->{out},
                    qr/Uploaded iOS build to App Store Connect\./,
                    'upload success is reported'
                );
                my $message = index( $result->{out}, 'Uploaded iOS build' );
                cmp_ok( index( $result->{out}, 'MOCK_EXPORT_COMPLETED' ),
                    '<', $message, 'success is printed after exporter finishes' );
            }
        }
    }
};

subtest 'App Store command failures stop without exporting an incomplete archive' => sub {
    for my $mode ( '--app-store', '--upload' ) {
        for my $operation (qw(settings archive export)) {
            my ( $tmp,    $project ) = fixture();
            my ( $result, $events )  = invoke( $tmp, $project, [$mode], fail => $operation );
            is( $result->{code},          29,           "$operation failure is preserved" );
            is( $events->[-1]{operation}, $operation,   'no commands after failure' );
            is( $_->{command},            'xcodebuild', 'no device side effects after failure' ) for @$events;
            unlike(
                $result->{out},
                qr{App Store (?:IPA|export):|Uploaded iOS build},
                'no success message on failure'
            );
        }
    }
};

subtest 'local iOS export resets a reused upload directory to export mode' => sub {
    my ( $tmp,      $project ) = fixture();
    my ( $uploaded, $first )   = invoke( $tmp, $project, [ '--upload', 'shared output' ] );
    is( $uploaded->{code}, 0, $uploaded->{err} );
    like(
        $first->[-1]{exportOptions},
        qr{<key>destination</key>\s*<string>upload</string>},
        'explicit upload selected'
    );
    my ( $exported, $second ) = invoke( $tmp, $project, [ '--app-store', 'shared output' ] );
    is( $exported->{code}, 0, $exported->{err} );
    like(
        $second->[-1]{exportOptions},
        qr{<key>destination</key>\s*<string>export</string>},
        'later local export cannot inherit upload'
    );
    unlike( $exported->{out}, qr/Uploaded iOS build/, 'local export does not report upload' );
    like(
        read_text("$project/deploy/ios-export.plist"),
        qr{<key>destination</key>\s*<string>export</string>},
        'source template remains local'
    );
};

subtest 'invalid or missing app signing settings stop before archive' => sub {
    for my $mode ( '--app-store', '--upload' ) {
        for my $settings (
            'not JSON', '[]',
            '[{"target":"leqra","buildSettings":{"DEVELOPMENT_TEAM":""}}]',
            '[{"target":"leqraUITests","buildSettings":{"DEVELOPMENT_TEAM":"WRONGTEAM"}}]'
          )
        {
            my ( $tmp,    $project ) = fixture();
            my ( $result, $events )  = invoke( $tmp, $project, [$mode], settings => $settings );
            isnt( $result->{code}, 0, 'invalid settings rejected' );
            is_deeply( [ map { $_->{operation} } @$events ], ['settings'], 'no archive or export' );
        }
    }
};

subtest 'the original device mode still builds installs and launches the named iPhone' => sub {
    my ( $tmp,    $project ) = fixture();
    my ( $result, $events )  = invoke( $tmp, $project, ['iPhone with spaces'] );
    is( $result->{code}, 0, $result->{err} );
    is_deeply( [ map { $_->{command} } @$events ], [qw(xcodebuild xcrun xcrun)], 'original device commands' );
    is_deeply( [ map { $_->{operation} } @$events ], [qw(build install launch)], 'original operation order' );
    is( flag( $events->[0], '-destination' ), 'platform=iOS,name=iPhone with spaces', 'requested device' );
    is( flag( $events->[0], '-configuration' ),   'Release',               'release device build' );
    is( flag( $events->[0], '-derivedDataPath' ), '/tmp/leqra-ios-device', 'existing device build location' );
    is_deeply(
        $events->[1]{args},
        [
            'devicectl', 'device', 'install', 'app', '--device',
            'iPhone with spaces',
            '/tmp/leqra-ios-device/Build/Products/Release-iphoneos/leqra.app'
        ],
        'device install'
    );
    is_deeply(
        $events->[2]{args},
        [
            'devicectl', 'device',             'process',              'launch',
            '--device',  'iPhone with spaces', '--terminate-existing', 'com.leqra'
        ],
        'device launch'
    );
};

subtest 'device mode failures stop before the next device action' => sub {
    for my $operation (qw(build install launch)) {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = invoke( $tmp, $project, ['iPhone'], fail => $operation );
        is( $result->{code},          29,         "$operation failure preserved" );
        is( $events->[-1]{operation}, $operation, 'no later device action' );
    }
};

subtest 'invalid arguments do not invoke build or device tools' => sub {
    for my $arguments (
        [], ['--unknown'],
        [ 'one',         'two' ],
        [ '--app-store', 'one', 'two' ],
        [ '--upload',    'one', 'two' ],
        [ '--app-store', '--upload' ],
        [ '--upload',    '--app-store' ]
      )
    {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = invoke( $tmp, $project, $arguments );
        isnt( $result->{code}, 0, 'invalid invocation rejected' );
        is_deeply( $events, [], 'no tool actions' );
    }
};

done_testing;
