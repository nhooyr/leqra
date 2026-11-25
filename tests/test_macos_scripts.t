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
use File::Path qw(make_path remove_tree);
my $command=basename($0);
my $operation=$command eq 'xcodebuild' ? $ARGV[-1] : $command;
$operation='export' if grep { $_ eq '-exportArchive' } @ARGV;
my $record={command=>$command,operation=>$operation,args=>\@ARGV,cwd=>getcwd(),home=>$ENV{HOME},team=>$ENV{DEVELOPMENT_TEAM}};
if ($operation eq 'export') {
    my ($index)=grep { $ARGV[$_] eq '-exportOptionsPlist' } 0..$#ARGV;
    if (defined $index) {
        open my $options,'<',$ARGV[$index+1] or die $!;
        $record->{exportOptions}=do {local $/;<$options>};
    }
}
open my $out,'>>',$ENV{MACOS_TRACE} or die $!;
print {$out} encode_json($record),"\n";
close $out;
exit 29 if $ENV{MACOS_FAIL} && grep { $_ eq $ENV{MACOS_FAIL} } @ARGV;
if ($command eq 'xcodebuild' && $operation eq 'build') {
    my ($index)=grep { $ARGV[$_] eq '-derivedDataPath' } 0..$#ARGV;
    my $app="$ARGV[$index+1]/Build/Products/Release-maccatalyst/leqra.app";
    make_path("$app/Contents/MacOS");
    open my $binary,'>',"$app/Contents/MacOS/leqra" or die $!;
    print {$binary} "new local build\n";
    close $binary;
    chmod 0755,"$app/Contents/MacOS/leqra" or die $!;
    open my $plist,'>',"$app/Contents/Info.plist" or die $!;
    print {$plist} '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.leqra</string></dict></plist>';
    close $plist;
}
if ($command eq 'codesign') {
    my $staged=index($ARGV[-1],"$ENV{LEQRA_MACOS_INSTALL_DIR}/")==0 && $ARGV[-1] ne "$ENV{LEQRA_MACOS_INSTALL_DIR}/leqra.app";
    exit 29 if ($ENV{MACOS_FAIL}//'') eq 'codesign' || $staged && ($ENV{MACOS_FAIL}//'') eq 'staged-codesign';
    remove_tree($ARGV[-1]) if $staged && ($ENV{MACOS_FAIL}//'') eq 'remove-staged';
}
die 'The deploy script must not launch an app' if $command eq 'open';
print "MOCK_EXPORT_COMPLETED\n" if $operation eq 'export';
PERL

sub fixture {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    copy_file( root() . '/ci/macos.sh',               "$project/ci/macos.sh" );
    copy_file( root() . '/deploy/macos.sh',           "$project/deploy/macos.sh" );
    copy_file( root() . '/deploy/macos-export.plist', "$project/deploy/macos-export.plist" );
    write_text( "$tmp/commands/$_", $recorder, 0755 ) for qw(swift xcodebuild codesign open);
    make_path("$tmp/unrelated directory");
    return ( $tmp, $project );
}

sub run_script {
    my ( $tmp, $project, $script, $arguments, %options ) = @_;
    my %env = (
        %ENV,
        PATH                    => "$tmp/commands:$ENV{PATH}",
        RUNNER_TEMP             => "$tmp/build temporary",
        MACOS_TRACE             => "$tmp/trace",
        MACOS_FAIL              => $options{fail} // '',
        LEQRA_MACOS_INSTALL_DIR => "$tmp/local Applications",
    );
    delete $env{DEVELOPMENT_TEAM};
    $env{DEVELOPMENT_TEAM} = $options{team} if exists $options{team};
    my $result = run_cmd(
        [ 'sh', "$project/$script", @$arguments ],
        cwd => "$tmp/unrelated directory",
        env => \%env
    );
    return ( $result, -e "$tmp/trace" ? json_lines("$tmp/trace") : [] );
}

sub flag {
    my ( $event, $flag ) = @_;
    my ($index) =
      grep { $event->{args}[$_] eq $flag } 0 .. $#{ $event->{args} };
    return defined($index) ? $event->{args}[ $index + 1 ] : undef;
}

subtest 'Mac CI compiles Catalyst regression tests without launching a GUI' => sub {
    my ( $tmp,    $project ) = fixture();
    my ( $result, $events )  = run_script( $tmp, $project, 'ci/macos.sh', [] );
    is( $result->{code}, 0, $result->{err} );
    is_deeply(
        [ map { $_->{command} } @$events ],
        [qw(swift swift xcodebuild swift)],
        'restore, shared regression tests, compile Catalyst app and UI regression tests, save'
    );
    is( $_->{cwd},              $project,  'commands run from repository root' ) for @$events;
    is( $events->[0]{args}[-2], 'restore', 'restore source timestamps' );
    is( $events->[0]{args}[-1], "$tmp/build temporary/leqra-macos-inputs.json", 'Mac-specific manifest' );
    is(
        flag( $events->[1], '--scratch-path' ),
        "$tmp/build temporary/leqra-macos-swift",
        'Mac-specific Swift cache'
    );
    is( flag( $events->[2], '-destination' ), 'platform=macOS,variant=Mac Catalyst', 'Catalyst destination' );
    is(
        flag( $events->[2], '-derivedDataPath' ),
        "$tmp/build temporary/leqra-macos",
        'Mac-specific build cache'
    );
    is(
        flag( $events->[2], '-resultBundlePath' ),
        "$tmp/build temporary/leqra-macos-tests.xcresult",
        'Mac-specific results'
    );
    ok(
        !grep( /^-(?:only|skip)-testing:/, @{ $events->[2]{args} } ),
        'compile the full Catalyst regression test target'
    );
    ok( grep( $_ eq 'CODE_SIGN_IDENTITY=-', @{ $events->[2]{args} } ), 'CI uses local signing' );
    ok(
        grep( $_ eq 'CODE_SIGN_ENTITLEMENTS=', @{ $events->[2]{args} } ),
        'compile-only CI does not request provisioned Keychain access'
    );
    ok(
        !grep( $_ eq '-allowProvisioningUpdates', @{ $events->[2]{args} } ),
        'compile-only CI does not provision a developer account'
    );
    ok(
        grep( $_ eq 'ENABLE_HARDENED_RUNTIME=NO', @{ $events->[2]{args} } ),
        'ad-hoc CI runner can load its regression test bundle'
    );
    is( $events->[2]{args}[-1],
        'build-for-testing', 'compile the app and regression tests without launching them' );
    is( $events->[3]{args}[-2], 'save', 'save cache metadata after success' );
};

subtest 'Mac CI preserves failures and never saves a failed build' => sub {
    for my $failure ( 'restore', 'test', 'build-for-testing' ) {
        my ( $tmp, $project ) = fixture();
        my ( $result, $events ) =
          run_script( $tmp, $project, 'ci/macos.sh', [], fail => $failure );
        is( $result->{code}, 29, 'exit status preserved' );
        ok( !grep( $_->{args}[-2] eq 'save', @$events ), 'no cache metadata saved after failure' );
    }
};

sub installed_fixture {
    my ($tmp) = @_;
    my $install = "$tmp/local Applications";
    write_text( "$install/leqra.app/Contents/MacOS/leqra", "old installed build\n", 0755 );
    write_text( "$install/Other.app/sentinel", 'unrelated app' );
    return $install;
}

subtest 'default Mac deployment preserves signing and atomically installs a local universal app' => sub {
    for my $existing ( 0, 1 ) {
        my ( $tmp, $project ) = fixture();
        my $install = installed_fixture($tmp);
        if ( !$existing ) {
            require File::Path;
            File::Path::remove_tree("$install/leqra.app");
        }
        my ( $result, $events ) = run_script( $tmp, $project, 'deploy/macos.sh', [], team => 'KEYCHAINTEAM' );
        is( $result->{code}, 0, $result->{err} );
        my @builds = grep { $_->{command} eq 'xcodebuild' } @$events;
        is( scalar @builds, 1, 'one build, no archive or export' );
        my $build = $builds[0];
        is( $build->{operation},              'build',   'local build action' );
        is( flag( $build, '-configuration' ), 'Release', 'release optimization' );
        is(
            flag( $build, '-destination' ),
            'platform=macOS,variant=Mac Catalyst',
            'provision the current Mac while building Catalyst'
        );
        ok( grep( $_ eq 'ONLY_ACTIVE_ARCH=NO', @{ $build->{args} } ), 'universal architecture selection' );
        ok(
            !grep( /\A(?:CODE_SIGN_IDENTITY|CODE_SIGNING_ALLOWED|CODE_SIGN_ENTITLEMENTS|DEVELOPMENT_TEAM)=/,
                @{ $build->{args} } ),
            'local app retains project signing, team and Keychain entitlements'
        );
        ok(
            grep( $_ eq '-allowProvisioningUpdates', @{ $build->{args} } ),
            'local app can obtain the profile required for Keychain access'
        );
        ok(
            grep( $_ eq '-allowProvisioningDeviceRegistration', @{ $build->{args} } ),
            'local app can register this Mac with the development profile'
        );
        is( $build->{team}, 'KEYCHAINTEAM', 'caller development team is retained' );
        is(
            read_text("$project/bin/macos/leqra.app/Contents/MacOS/leqra"),
            "new local build\n",
            'local build artifact remains available'
        );
        is( read_text("$install/leqra.app/Contents/MacOS/leqra"), "new local build\n", 'new app installed' );
        is( read_text("$install/Other.app/sentinel"), 'unrelated app', 'other installed apps are preserved' );
        my @checks = grep { $_->{command} eq 'codesign' } @$events;
        ok( @checks, 'signature verified before installation' );
        ok(
            grep( index( $_->{args}[-1], "$install/" ) == 0 && $_->{args}[-1] ne "$install/leqra.app",
                @checks ),
            'staged app signature verified'
        );
        is( $_->{home}, $ENV{HOME}, 'HOME unchanged' ) for @$events;
        ok( !grep( $_->{command} eq 'open', @$events ), 'installed app is not launched' );
    }
};

subtest 'Mac Keychain access uses the provisioned application identity' => sub {
    my $entitlements = read_text( root() . '/ios/leqra/leqra-mac.entitlements' );
    my $group        = '$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)';
    like(
        $entitlements,
        qr{<key>keychain-access-groups</key>\s*<array>\s*<string>\Q$group\E</string>\s*</array>},
        'Keychain access group follows the signing prefix and bundle identifier'
    );
};

subtest 'failed local Mac builds and verification preserve the installed app' => sub {
    for my $failure ( 'build', 'codesign', 'staged-codesign', 'remove-staged' ) {
        my ( $tmp, $project ) = fixture();
        my $install = installed_fixture($tmp);
        write_text( "$project/bin/macos/leqra.app/Contents/MacOS/leqra", "prior local artifact\n", 0755 );
        my ( $result, $events ) = run_script( $tmp, $project, 'deploy/macos.sh', [], fail => $failure );
        isnt( $result->{code}, 0, "$failure is reported" );
        is(
            read_text("$install/leqra.app/Contents/MacOS/leqra"),
            "old installed build\n",
            "$failure keeps existing app"
        );
        is( read_text("$install/Other.app/sentinel"), 'unrelated app', "$failure keeps other apps" );
        is(
            read_text("$project/bin/macos/leqra.app/Contents/MacOS/leqra"),
            "prior local artifact\n",
            "$failure keeps prior build artifact"
        );
        ok(
            !grep( $_->{command} eq 'open' || $_->{operation} eq 'export' || $_->{operation} eq 'archive',
                @$events ),
            'no launch or distribution work after failure'
        );
    }
};

subtest 'Mac App Store export and explicit upload never install or launch' => sub {
    for my $mode ( [ '--app-store', 'export' ], [ '--upload', 'upload' ] ) {
        for my $custom ( 0, 1 ) {
            my ( $tmp, $project ) = fixture();
            my $template  = read_text("$project/deploy/macos-export.plist");
            my $install   = installed_fixture($tmp);
            my @arguments = ( $mode->[0], $custom ? ('custom store output') : () );
            my ( $result, $events ) = run_script( $tmp, $project, 'deploy/macos.sh', \@arguments );
            is( $result->{code}, 0, $result->{err} );
            is_deeply(
                [ map { $_->{command} } @$events ],
                [qw(xcodebuild xcodebuild)],
                'archive and export only'
            );
            my ( $archive, $export ) = @$events;
            my $output = "$project/" . ( $custom ? 'custom store output' : 'bin/macos' );
            is(
                flag( $archive, '-destination' ),
                'generic/platform=macOS,variant=Mac Catalyst',
                'generic Catalyst archive'
            );
            is( flag( $archive, '-configuration' ), 'Release', 'release archive' );
            is( $archive->{operation},              'archive', 'archive action' );
            ok( grep( $_ eq 'ONLY_ACTIVE_ARCH=NO', @{ $archive->{args} } ), 'universal archive' );
            ok(
                !grep( $_ eq 'CODE_SIGN_IDENTITY=-'
                      || $_ eq 'CODE_SIGNING_ALLOWED=NO'
                      || $_ eq 'DEVELOPMENT_TEAM=',
                    @{ $archive->{args} } ),
                'distribution archive keeps automatic signing'
            );
            is( flag( $archive, '-archivePath' ), "$output/leqra.xcarchive", 'archive path' );
            is( $export->{operation},             'export',                  'export action' );
            is( flag( $export, '-archivePath' ), "$output/leqra.xcarchive", 'exports the completed archive' );
            is(
                flag( $export, '-exportPath' ),
                $mode->[1] eq 'export' ? "$output/export" : undef,
                'export path applies only to local export'
            );
            is(
                flag( $export, '-exportOptionsPlist' ),
                "$output/ExportOptions.plist",
                'uses copied export options'
            );
            like(
                $export->{exportOptions},
                qr{<key>destination</key>\s*<string>\Q$mode->[1]\E</string>},
                'requested distribution destination'
            );
            like(
                $export->{exportOptions},
                qr{<key>manageAppVersionAndBuildNumber</key>\s*<false\s*/>},
                'version auto-management stays disabled'
            );
            is( read_text("$project/deploy/macos-export.plist"), $template, 'source template is unchanged' );
            ok(
                grep( $_ eq '-allowProvisioningUpdates', @{ $export->{args} } ),
                'explicit store export enables account provisioning'
            );
            is(
                read_text("$install/leqra.app/Contents/MacOS/leqra"),
                "old installed build\n",
                'store export does not install over the local app'
            );
            is( $_->{home}, $ENV{HOME}, 'HOME unchanged' ) for @$events;

            if ( $mode->[1] eq 'upload' ) {
                like(
                    $result->{out},
                    qr/Uploaded macOS build to App Store Connect\./,
                    'upload success is reported'
                );
                cmp_ok(
                    index( $result->{out}, 'MOCK_EXPORT_COMPLETED' ),
                    '<',
                    index( $result->{out}, 'Uploaded macOS build' ),
                    'success printed only after exporter completes'
                );
            }
        }
    }
    my $plist = read_text( root() . '/deploy/macos-export.plist' );
    like(
        $plist,
        qr{<key>method</key>\s*<string>app-store-connect</string>},
        'Mac App Store distribution method'
    );
    like( $plist, qr{<key>destination</key>\s*<string>export</string>},     'local export, never upload' );
    like( $plist, qr{<key>manageAppVersionAndBuildNumber</key>\s*<false/>}, 'preserve project version' );
};

subtest 'local Mac export resets a reused upload directory to export mode' => sub {
    my ( $tmp, $project ) = fixture();
    my $install = installed_fixture($tmp);
    my ( $uploaded, $first ) =
      run_script( $tmp, $project, 'deploy/macos.sh', [ '--upload', 'shared output' ] );
    is( $uploaded->{code}, 0, $uploaded->{err} );
    like(
        $first->[-1]{exportOptions},
        qr{<key>destination</key>\s*<string>upload</string>},
        'explicit upload selected'
    );
    my ( $exported, $second ) =
      run_script( $tmp, $project, 'deploy/macos.sh', [ '--app-store', 'shared output' ] );
    is( $exported->{code}, 0, $exported->{err} );
    like(
        $second->[-1]{exportOptions},
        qr{<key>destination</key>\s*<string>export</string>},
        'later local export cannot inherit upload'
    );
    unlike( $exported->{out}, qr/Uploaded macOS build/, 'local export does not report upload' );
    like(
        read_text("$project/deploy/macos-export.plist"),
        qr{<key>destination</key>\s*<string>export</string>},
        'source template remains local'
    );
    is(
        read_text("$install/leqra.app/Contents/MacOS/leqra"),
        "old installed build\n",
        'repeated distribution commands never install'
    );
};

subtest 'Mac deployment help and Fish completions do no build or install work' => sub {
    for my $option ( '-h', '--help', '--fish-completions' ) {
        my ( $tmp, $project ) = fixture();
        my $install = installed_fixture($tmp);
        my ( $result, $events ) = run_script( $tmp, $project, 'deploy/macos.sh', [$option] );
        is( $result->{code}, 0, "$option succeeds" );
        is_deeply( $events, [], "$option invokes no build, signing or launch command" );
        is(
            read_text("$install/leqra.app/Contents/MacOS/leqra"),
            "old installed build\n",
            "$option preserves the installed app"
        );
        ok( !-e "$project/bin/macos", "$option creates no build output" );
        if ( $option eq '--fish-completions' ) {
            unlike( $result->{out}, qr/Usage:/, 'completion output contains only Fish commands' );
            my @lines = grep { length } split /\n/, $result->{out};
            ok( @lines && !grep( !/^complete -c macos\.sh /, @lines ),
                'completion commands target macos.sh' );
            like( $result->{out}, qr/ -s h -l help /, 'completion includes help' );
            like( $result->{out}, qr/ -l \Q$_\E /,    "completion includes $_" )
              for qw(app-store upload fish-completions);
        }
        else {
            like(
                $result->{out},
                qr/Usage: macos\.sh .*--app-store\|--upload/,
                'usage describes store modes'
            );
            like( $result->{out}, qr/Apple development signing/, 'help explains local signing' );
        }
        my ( $invalid, $invalid_events ) =
          run_script( $tmp, $project, 'deploy/macos.sh', [ $option, 'extra' ] );
        isnt( $invalid->{code}, 0, "$option rejects an extra argument" );
        is_deeply( $invalid_events, [], 'invalid help invocation performs no tool actions' );
    }
};

subtest 'store failures stop and invalid arguments do no work' => sub {
    for my $mode ( '--app-store', '--upload' ) {
        for my $failure ( 'archive', '-exportArchive' ) {
            my ( $tmp, $project ) = fixture();
            my $install = installed_fixture($tmp);
            my ( $result, $events ) =
              run_script( $tmp, $project, 'deploy/macos.sh', [$mode], fail => $failure );
            is( $result->{code}, 29,                            'distribution failure preserved' );
            is( scalar @$events, $failure eq 'archive' ? 1 : 2, 'no action after failure' );
            is(
                read_text("$install/leqra.app/Contents/MacOS/leqra"),
                "old installed build\n",
                'failed distribution preserves local app'
            );
            unlike( $result->{out}, qr/Uploaded macOS build/, 'failed command never reports upload success' );
        }
    }
    for my $arguments (
        ['unknown'], ['--unknown'],
        [ '--app-store', 'one', 'two' ],
        [ '--upload',    'one', 'two' ],
        [ '--app-store', '--upload' ],
        [ '--upload',    '--app-store' ]
      )
    {
        my ( $tmp,    $project ) = fixture();
        my ( $result, $events )  = run_script( $tmp, $project, 'deploy/macos.sh', $arguments );
        isnt( $result->{code}, 0, 'invalid arguments rejected' );
        is_deeply( $events, [], 'no external tools on invalid arguments' );
    }
};

done_testing;
