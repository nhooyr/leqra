use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;
use Digest::SHA qw(sha256_hex);

my $support=scratch();
write_text("$support/timestamps.swift",<<'SWIFT');
import Darwin
import Foundation
let args=Array(CommandLine.arguments.dropFirst())
if args[0] == "set" {
    let value=Int64(args[1])!
    let times=[timespec(tv_sec:0,tv_nsec:Int(UTIME_OMIT)),timespec(tv_sec:Int(value/1_000_000_000),tv_nsec:Int(value%1_000_000_000))]
    for path in args.dropFirst(2) {
        guard utimensat(AT_FDCWD,path,times,AT_SYMLINK_NOFOLLOW) == 0 else { fatalError("utimensat failed") }
    }
} else {
    var result=[String:Int64]()
    for path in args.dropFirst() {
        var info=stat()
        guard fstatat(AT_FDCWD,path,&info,AT_SYMLINK_NOFOLLOW) == 0 else { fatalError("stat failed") }
        result[path]=Int64(info.st_mtimespec.tv_sec)*1_000_000_000+Int64(info.st_mtimespec.tv_nsec)
    }
    print(String(data:try JSONEncoder().encode(result),encoding:.utf8)!)
}
SWIFT
my $compile=run_cmd(['swiftc','-module-cache-path',"$support/modules","$support/timestamps.swift",'-o',"$support/timestamps"]);
BAIL_OUT($compile->{err}) if $compile->{code};
sub set_times {
    my ($nanoseconds,@paths)=@_;
    my $r=run_cmd(["$support/timestamps",'set',"$nanoseconds",@paths]);
    die $r->{err} if $r->{code};
}
sub timestamps {
    my $r=run_cmd(["$support/timestamps",'get',@_]);
    die $r->{err} if $r->{code};
    return decode_json($r->{out});
}
sub cache_fixture {
    my $tmp=scratch();
    copy_file(root().'/ci/ios-cache.swift',"$tmp/ci/ios-cache.swift");
    make_path("$tmp/unrelated working directory");
    is(run_cmd(['git','init','-q'],cwd=>$tmp)->{code},0,'init');
    return $tmp;
}
sub cache_command {
    my ($tmp,$action,$manifest)=@_;
    my $r=run_cmd(['swift','-module-cache-path',"$support/modules","$tmp/ci/ios-cache.swift",$action,$manifest],cwd=>"$tmp/unrelated working directory");
    is($r->{code},0,$r->{err});
    return $r;
}
subtest 'only identical existing build inputs regain exact cached timestamp' => sub {
    my $tmp=cache_fixture();
    my @files=('ios/same.swift','ios/changed.swift','ios/deleted.swift','ios/replaced.swift','scripts/ios-version.sh','scripts/version.sh','src/main.go','unrelated.swift');
    my $original=1_600_000_000_123_456_789; my $newer=$original+5_000_000_000;
    write_text("$tmp/$_",'original') for @files;
    set_times($original,map {"$tmp/$_"} @files);
    is(run_cmd(['git','add','.'],cwd=>$tmp)->{code},0,'add');
    write_text("$tmp/ios/untracked.swift",'original'); set_times($original,"$tmp/ios/untracked.swift");
    cache_command($tmp,'save',"$tmp/cache/inputs.json");
    my $records=decode_json(read_text("$tmp/cache/inputs.json"));
    is_deeply($records->{'ios/same.swift'},{sha256=>sha256_hex('original'),mtime_ns=>$original},'existing JSON schema retains exact integer nanoseconds');
    ok(exists $records->{'ios/untracked.swift'},'untracked input included');
    ok(!exists $records->{'unrelated.swift'},'unrelated file excluded');
    set_times($newer,map {"$tmp/$_"} @files,'ios/untracked.swift');
    write_text("$tmp/ios/changed.swift",'modified'); set_times($newer,"$tmp/ios/changed.swift");
    unlink "$tmp/ios/deleted.swift" or die $!;
    unlink "$tmp/ios/replaced.swift" or die $!;
    symlink "$tmp/unrelated.swift","$tmp/ios/replaced.swift" or die $!;
    symlink "$tmp/unrelated.swift","$tmp/ios/link.swift" or die $!;
    write_text("$tmp/ios/new.swift",'new');
    set_times($newer,map {"$tmp/$_"} ('ios/new.swift','ios/replaced.swift','ios/link.swift'));
    my $r=cache_command($tmp,'restore',"$tmp/cache/inputs.json");
    like($r->{out},qr/Restored timestamps for 5 unchanged iOS build inputs/,'only unchanged regular inputs restored');
    my $times=timestamps(map {"$tmp/$_"} grep {$_ ne 'ios/deleted.swift'} @files,'ios/untracked.swift','ios/new.swift','ios/link.swift');
    is($times->{"$tmp/$_"},$original,"$_ restored to exact nanosecond") for ('ios/same.swift','scripts/ios-version.sh','scripts/version.sh','src/main.go','ios/untracked.swift');
    is($times->{"$tmp/$_"},$newer,"$_ untouched") for ('ios/changed.swift','ios/new.swift','ios/replaced.swift','ios/link.swift','unrelated.swift');
    is(read_text("$tmp/ios/changed.swift"),'modified','changed content retained'); ok(!-e "$tmp/ios/deleted.swift",'deletion retained');
    cache_command($tmp,'save',"$tmp/cache/roundtrip.json");
    my $roundtrip=decode_json(read_text("$tmp/cache/roundtrip.json"));
    is_deeply($roundtrip->{'ios/same.swift'},$records->{'ios/same.swift'},'save after restore preserves exact timestamp and digest');
    ok(!exists $roundtrip->{'ios/replaced.swift'} && !exists $roundtrip->{'ios/link.swift'},'symlinks excluded from saved inputs');
};
subtest 'cold cache leaves timestamps alone' => sub {
    my $tmp=cache_fixture(); write_text("$tmp/ios/source.swift",'source');
    my $before=timestamps("$tmp/ios/source.swift"); cache_command($tmp,'restore',"$tmp/missing.json");
    is_deeply(timestamps("$tmp/ios/source.swift"),$before,'timestamp unchanged');
    ok(!-e "$tmp/missing.json",'cold restore does not create a manifest');
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
