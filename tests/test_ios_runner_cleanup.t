use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;
use XML::Parser;
my $runner='com.leqra.uitests.xctrunner';
sub cleanup {
    my ($platform,%options)=@_; my $tmp=scratch();
    write_text("$tmp/xcrun",<<'PERL',0755);
#!/usr/bin/perl
use JSON::PP;
print STDERR encode_json(\@ARGV),"\nDEVELOPER_DIR=",$ENV{DEVELOPER_DIR}//'',"\n";
exit 19 if exists($ENV{MOCK_EXPECTED_DEVELOPER}) && ($ENV{DEVELOPER_DIR}//'') ne $ENV{MOCK_EXPECTED_DEVELOPER};
exit($ENV{MOCK_EXIT}//0);
PERL
    my %env=(%ENV,PATH=>"$tmp:$ENV{PATH}",TARGET_DEVICE_IDENTIFIER=>$options{device}//'selected destination',TARGET_DEVICE_PLATFORM_NAME=>$platform,MOCK_EXIT=>$options{status}//0);
    for my $pair (['DEVELOPER_DIR','developer_dir'],['DEVELOPER_BIN_DIR','developer_bin'],['MOCK_EXPECTED_DEVELOPER','expected_developer']) {
        delete $env{$pair->[0]}; $env{$pair->[0]}=$options{$pair->[1]} if defined $options{$pair->[1]};
    }
    my $r=run_cmd([root().'/scripts/cleanup-ios-test-runner.sh'],cwd=>$tmp,env=>\%env);
    my @commands=map {decode_json($_)} grep {/^\[/} split /\n/,$r->{err};
    return ($r,\@commands);
}
subtest 'simulator targets selected device and runner only' => sub {
    for my $p ('iphonesimulator','com.apple.platform.iphonesimulator','iOS Simulator') {
        my ($r,$c)=cleanup($p); is($r->{code},0,$r->{err});
        is_deeply($c,[['simctl','uninstall','selected destination',$runner]],$p);
    }
};
subtest 'physical cleanup is bounded and never uninstalls game' => sub {
    for my $p ('iphoneos','com.apple.platform.iphoneos','iOS') {
        my ($r,$c)=cleanup($p); is($r->{code},0,$r->{err});
        is_deeply($c,[['devicectl','device','uninstall','app','--device','selected destination',$runner,'--timeout','15','--quiet']],$p);
        ok(!grep($_ eq 'com.leqra',@{$c->[0]}),'game is untouched');
    }
};
subtest 'missing generic and unsupported destinations are untouched' => sub {
    for my $case (['iphoneos',''],['iphoneos','dvtdevice-placeholder'],['iphonesimulator','AnySimulatorPlaceholder'],['macosx','host'],['','unknown']) {
        my ($r,$c)=cleanup($case->[0],device=>$case->[1]); is($r->{code},0,'status'); is_deeply($c,[],'no command');
    }
};
subtest 'unavailable device reports retry without masking test result' => sub {
    for my $p ('iphoneos','iphonesimulator') {
        my ($r,$c)=cleanup($p,status=>17); is($r->{code},0,'status'); is(scalar @$c,1,'one command');
        like($r->{err},qr/warning:/,'warning'); like($r->{err},qr/retry before Run/,'retry');
    }
};
subtest 'missing scheme developer environment selects full Xcode' => sub {
    my $developer='/Applications/Xcode.app/Contents/Developer';
    for my $p ('iphonesimulator','iphoneos') { for my $dir (undef,'') {
        my ($r,$c)=cleanup($p,developer_dir=>$dir,expected_developer=>$developer);
        is($r->{code},0,'status'); is(scalar @$c,1,'one command'); like($r->{err},qr/\QDEVELOPER_DIR=$developer\E\n/,'Xcode'); unlike($r->{err},qr/warning:/,'no warning');
    } }
};
for my $case (
    ['scheme developer bin selects Xcode with spaces','iphonesimulator',{developer_bin=>'/Applications/Xcode Custom.app/Contents/Developer/usr/bin'},'/Applications/Xcode Custom.app/Contents/Developer'],
    ['explicit developer directory takes precedence','iphoneos',{developer_dir=>'/Applications/Xcode Selected.app/Contents/Developer',developer_bin=>'/Applications/Other.app/Contents/Developer/usr/bin'},'/Applications/Xcode Selected.app/Contents/Developer'],
    ['standalone command line tools do not override Xcode','iphonesimulator',{developer_bin=>'/Library/Developer/CommandLineTools/usr/bin'},'/Applications/Xcode.app/Contents/Developer']) {
    subtest $case->[0] => sub {
        my ($r,$c)=cleanup($case->[1],%{$case->[2]},expected_developer=>$case->[3]);
        is($r->{code},0,'status'); is(scalar @$c,1,'one command'); unlike($r->{err},qr/warning:/,'no warning');
    };
}
sub tree_path {
    my ($node,@path)=@_; return $node unless @path;
    my $name=shift @path;
    for (my $i=1;$i<@$node;$i+=2) { return tree_path($node->[$i+1],@path) if $node->[$i] eq $name; }
    return;
}
subtest 'shared scheme cleans after testing and before normal run' => sub {
    my $tree=XML::Parser->new(Style=>'Tree')->parsefile(root().'/ios/leqra.xcodeproj/xcshareddata/xcschemes/leqra.xcscheme');
    for my $path (['TestAction','PostActions'],['LaunchAction','PreActions']) {
        my $content=tree_path($tree->[1],@$path,'ExecutionAction','ActionContent');
        ok($content,'action exists'); (my $script=$content->[0]{scriptText}) =~ s/^\s+|\s+$//g;
        is($script,'"${SRCROOT}/../scripts/cleanup-ios-test-runner.sh"','script');
        is(tree_path($content,'EnvironmentBuildable','BuildableReference')->[0]{BlueprintName},'leqraUITests','build environment');
    }
    is(tree_path($tree->[1],'TestAction','Testables','TestableReference')->[0]{skipped},'NO','Xcode still installs runner');
};
done_testing;
