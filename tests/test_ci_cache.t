use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;
use Time::HiRes ();
do(root().'/ci/ios-cache.pl') or die $@ || $!;
subtest 'only identical existing build inputs regain exact cached timestamp' => sub {
    my $tmp=scratch();
    my @files=('ios/same.swift','ios/changed.swift','ios/deleted.swift','scripts/version.sh','src/main.go','unrelated.swift');
    my $original=1_600_000_000_123_456_789; my $newer=$original+5_000_000_000;
    for (@files) { write_text("$tmp/$_",'original'); set_modification_time("$tmp/$_",$original); }
    is(run_cmd(['git','init','-q'],cwd=>$tmp)->{code},0,'init');
    is(run_cmd(['git','add','.'],cwd=>$tmp)->{code},0,'add');
    save($tmp,"$tmp/cache.json");
    set_modification_time("$tmp/$_",$newer) for @files;
    write_text("$tmp/ios/changed.swift",'modified'); set_modification_time("$tmp/ios/changed.swift",$newer);
    unlink "$tmp/ios/deleted.swift" or die $!;
    write_text("$tmp/ios/new.swift",'new'); set_modification_time("$tmp/ios/new.swift",$newer);
    symlink "$tmp/unrelated.swift","$tmp/ios/link.swift" or die $!;
    restore($tmp,"$tmp/cache.json");
    is(modification_time("$tmp/$_"),$original,"$_ restored to exact nanosecond") for ('ios/same.swift','scripts/version.sh','src/main.go');
    is(modification_time("$tmp/$_"),$newer,"$_ untouched") for ('ios/changed.swift','ios/new.swift','unrelated.swift');
    is(read_text("$tmp/ios/changed.swift"),'modified','changed content retained'); ok(!-e "$tmp/ios/deleted.swift",'deletion retained');
};
subtest 'cold cache leaves timestamps alone' => sub {
    my $tmp=scratch(); write_text("$tmp/source.swift",'source');
    my $before=modification_time("$tmp/source.swift"); restore($tmp,"$tmp/missing.json");
    is(modification_time("$tmp/source.swift"),$before,'timestamp unchanged');
};
subtest 'newest standard available runtime uses version metadata' => sub {
    my $old='com.apple.CoreSimulator.SimRuntime.iOS-26-5'; my $new='com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19';
    my $standard='com.apple.CoreSimulator.SimRuntime.iOS-27-2'; my $unavailable='com.apple.CoreSimulator.SimRuntime.iOS-28-0';
    my $inventory={runtimes=>[map {{identifier=>$_->[0],version=>$_->[1],isAvailable=>$_->[2]}} ([$old,'26.5',JSON::PP::true],[$new,'27.2',JSON::PP::true],[$standard,'27.2',JSON::PP::true],[$unavailable,'28.0',JSON::PP::false])],devices=>{$old=>[{name=>'iPhone old',udid=>'old',state=>'Booted',isAvailable=>JSON::PP::true}],$new=>[{name=>'iPhone new',udid=>'new',state=>'Shutdown',isAvailable=>JSON::PP::true}],$standard=>[{name=>'iPhone standard',udid=>'standard',state=>'Shutdown',isAvailable=>JSON::PP::true}]}};
    for my $state ('Shutdown','Booted') {
        my $tmp=scratch(); $inventory->{devices}{$standard}[0]{state}=$state; write_text("$tmp/inventory.json",encode_json($inventory));
        write_text("$tmp/xcrun",<<'PERL',0755);
#!/usr/bin/perl
use JSON::PP;
if ($ARGV[1] eq 'list') { open my $f,'<',$ENV{INVENTORY} or die $!; local $/; print <$f>; }
else { open my $f,'>>',$ENV{TRACE} or die $!; print {$f} encode_json(\@ARGV),"\n"; }
PERL
        my %env=(%ENV,PATH=>"$tmp:$ENV{PATH}",INVENTORY=>"$tmp/inventory.json",TRACE=>"$tmp/trace");
        my $r=run_cmd([$^X,root().'/ci/ios-simulator.pl'],env=>\%env);
        is($r->{code},0,$r->{err}); is($r->{out},"standard\n",'standard runtime chosen');
        is_deeply(-e "$tmp/trace" ? json_lines("$tmp/trace") : [],$state eq 'Shutdown' ? [['simctl','boot','standard']] : [],'boot only when shut down');
    }
};
subtest 'installed Android SDK reused and missing packages installed' => sub {
    for my $missing ('','platform','build-tools') {
        my $tmp=scratch(); copy_file(root().'/ci/android.sh',"$tmp/ci/android.sh");
        my $recorder=<<'PERL';
#!/usr/bin/perl
use JSON::PP; open my $f,'>>',$ENV{TRACE} or die $!; print {$f} encode_json([$0,@ARGV]),"\n";
PERL
        write_text("$tmp/$_",$recorder,0755) for ('android/gradlew','sdk/cmdline-tools/latest/bin/sdkmanager');
        write_text("$tmp/sdk/platforms/android-36/android.jar",'') unless $missing eq 'platform';
        write_text("$tmp/sdk/build-tools/36.0.0/aapt2",'',0755) unless $missing eq 'build-tools';
        my %env=(%ENV,ANDROID_HOME=>"$tmp/sdk",TRACE=>"$tmp/trace"); delete $env{GITHUB_ACTIONS};
        my $r=run_cmd(['sh',"$tmp/ci/android.sh"],env=>\%env); is($r->{code},0,$r->{err});
        my $commands=json_lines("$tmp/trace"); is(scalar @$commands,$missing ? 2 : 1,'command count');
        like($commands->[-1][0],qr{/gradlew$},'Gradle invocation');
        for my $task (qw(:core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleDebugAndroidTest)) { ok(grep($_ eq $task,@{$commands->[-1]}),$task); }
        is_deeply([@{$commands->[0]}[1..$#{$commands->[0]}]],['platforms;android-36','build-tools;36.0.0'],'packages') if $missing;
    }
};
done_testing;
