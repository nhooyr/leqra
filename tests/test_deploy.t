use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;

my $stub = <<'PERL';
#!/usr/bin/perl
use strict; use warnings; use JSON::PP; use File::Basename qw(basename); use Cwd qw(getcwd);
my $name=basename($0); my @args=@ARGV;
open my $log,'>>',$ENV{DEPLOY_TEST_LOG} or die $!;
print {$log} encode_json({command=>$name,args=>\@args,cwd=>getcwd(),goos=>$ENV{GOOS},goarch=>$ENV{GOARCH}}),"\n"; close $log;
if ($name eq 'go') {
    exit(($ENV{DEPLOY_TEST_ASSETS_FAIL}//'') eq '1' ? 6 : 0) if join(' ',@args) eq 'run ./src -check-assets';
    exit 7 if ($ENV{DEPLOY_TEST_GO_FAIL}//'') eq '1';
    die 'expected build' unless $args[0] eq 'build' && grep {$_ eq '-trimpath'} @args;
    for my $i (0..$#args-1) { if ($args[$i] eq '-o') { open my $f,'>',$args[$i+1] or die $!; print {$f} 'mock compiled executable'; close $f; last; } }
} elsif ($name eq 'ssh') {
    exit 8 if ($ENV{DEPLOY_TEST_SSH_FAIL}//'') eq '1';
    die 'unexpected host' unless shift(@args) eq 'leqra';
    $ENV{PATH}=$ENV{DEPLOY_TEST_BIN};
    system($args[0] eq 'sh' && $args[1] eq '-s' ? ('/bin/sh','-s') : @args); exit($? >> 8);
} elsif ($name eq 'rsync') {
    die 'missing source' unless -f $args[-2]; exit 9 if ($ENV{DEPLOY_TEST_RSYNC_FAIL}//'') eq '1';
} elsif ($name eq 'getent') { exit(($ENV{DEPLOY_TEST_NEW_USER}//'') eq '1' ? 1 : 0);
} elsif ($name eq 'sudo') {
    die 'unexpected sudo' unless $args[0] =~ /\A(?:useradd|mkdir|chown|systemctl)\z/;
    system("$ENV{DEPLOY_TEST_BIN}/$args[0]", @args[1..$#args]); exit($? >> 8);
} else { die "Unexpected mock command $name" unless $name =~ /\A(?:useradd|mkdir|chown|systemctl)\z/; }
PERL
sub deploy {
    my (%flags) = @_;
    my $tmp = scratch();
    my $project = "$tmp/project with spaces";
    my $dir = "$project/deploy";
    my $script = copy_file(root().'/deploy/server.sh', "$dir/server.sh");
    write_text("$dir/leqra.service", "[Service]\n"); write_text("$dir/leqra.env", "TEST=yes\n");
    write_text("$dir/leqra", 'preserve existing binary');
    my $bin = "$tmp/mock bin";
    write_text("$bin/$_", $stub, 0755) for qw(go ssh rsync getent useradd mkdir chown systemctl sudo);
    make_path("$tmp/build temp", "$tmp/unrelated cwd");
    my %env = map { $_ => $ENV{$_} } grep { !/^DEPLOY_TEST_/ } keys %ENV;
    @env{qw(PATH TMPDIR DEPLOY_TEST_LOG DEPLOY_TEST_BIN)} = ("$bin:/usr/bin:/bin", "$tmp/build temp", "$tmp/commands.jsonl", $bin);
    $env{"DEPLOY_TEST_$_"} = $flags{$_} for keys %flags;
    my $result = run_cmd(['/bin/sh',$script], cwd=>"$tmp/unrelated cwd",env=>\%env);
    my $events = json_lines("$tmp/commands.jsonl");
    is(read_text("$dir/leqra"),'preserve existing binary','existing binary is preserved');
    opendir my $files, "$tmp/build temp" or die $!;
    is_deeply([grep {!/^\.\.?$/} readdir $files],[],'build temporary files are removed');
    return ($result,$events,$project,"$tmp/build temp");
}
for my $new (0,1) {
    subtest($new ? 'new user' : 'existing user' => sub {
        my ($result,$events,$project,$build)=deploy(NEW_USER=>"$new");
        is($result->{code},0,$result->{err});
        my @names=map {$_->{command}} @$events;
        is_deeply([@names[0,1]],[qw(go go)],'check precedes build');
        is_deeply($events->[0]{args},['run','./src','-check-assets'],'assets checked');
        is(scalar(grep {$_ eq 'ssh'} @names),2,'two remote commands');
        is(scalar(grep {$_ eq 'useradd'} @names),$new,'user creation only when needed');
        is($events->[0]{cwd},$project,'project cwd');
        is_deeply([@{$events->[1]}{qw(goos goarch)}],[qw(linux amd64)],'target architecture');
        my ($mkdir)=grep {$_->{command} eq 'mkdir'} @$events;
        ok(grep($_ eq '/opt/leqra',@{$mkdir->{args}}),'server directory');
        ok(grep($_ eq '/etc/leqra',@{$mkdir->{args}}),'config directory');
        ok(grep($_ eq '/var/lib/leqra',@{$mkdir->{args}}),'data directory');
        my @transfers=map {$_->{args}} grep {$_->{command} eq 'rsync'} @$events;
        is_deeply([@{$_}[0..$#$_-2]],['--rsync-path=sudo rsync','-avz','--progress'],'transfer flags') for @transfers;
        is_deeply([map {$_->[-1]} @transfers],['leqra:/opt/leqra/leqra-server','leqra:/etc/systemd/system/leqra.service','leqra:/etc/leqra/leqra.env'],'destinations');
        like($transfers[0][-2],qr/^\Q$build\E\//,'build under temporary directory');
        my @controls=map {$_->{args}} grep {$_->{command} eq 'systemctl'} @$events;
        is_deeply([map {(grep {!/^-/} @$_)[0]} @controls],[qw(daemon-reload enable restart status)],'service actions');
        is_deeply([grep {!/^-/} @{$controls[-1]}],['status','leqra'],'service status');
    });
}
subtest 'asset failure stops before build and remote commands' => sub {
    my ($r,$e)=deploy(ASSETS_FAIL=>'1'); is($r->{code},6,'status');
    is_deeply([map {$_->{args}} @$e],[['run','./src','-check-assets']],'only asset check');
};
subtest 'build failure never contacts remote' => sub {
    my ($r,$e)=deploy(GO_FAIL=>'1'); isnt($r->{code},0,'failure');
    is_deeply([map {$_->{command}} @$e],[qw(go go)],'local commands only');
};
subtest 'ssh failure prevents transfer' => sub {
    my ($r,$e)=deploy(SSH_FAIL=>'1'); isnt($r->{code},0,'failure');
    is_deeply([map {$_->{command}} @$e],[qw(go go ssh)],'no transfers');
};
subtest 'transfer failure prevents service changes' => sub {
    my ($r,$e)=deploy(RSYNC_FAIL=>'1'); isnt($r->{code},0,'failure');
    is(scalar(grep {$_->{command} eq 'rsync'} @$e),1,'one transfer');
    is(scalar(grep {$_->{command} eq 'ssh'} @$e),1,'one remote setup');
    ok(!grep($_->{command} eq 'systemctl',@$e),'no service controls');
};
done_testing;
