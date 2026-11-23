use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;

my $stub = <<'PERL';
use strict;
use warnings;
use JSON::PP;
use File::Basename qw(basename);
use File::Path qw(make_path);
use Cwd qw(getcwd);
my $command=basename($0);
open my $log,'>>',$ENV{CI_PERL_LOG} or die $!;
print {$log} encode_json({command=>$command,args=>\@ARGV,cwd=>getcwd(),env=>{map {$_=>$ENV{$_}} qw(NODE_PATH PERL_CPANM_HOME PERL5LIB PATH)}}),"\n";
close $log;
if ($command eq 'perl' && $ARGV[0] eq '-e') {
    print 'v5.99.7';
} elsif ($command eq 'perl' && basename($ARGV[0]) eq 'cpanm') {
    exit 23 if $ENV{CI_PERL_FAIL};
    my ($index)=grep {$ARGV[$_] eq '--local-lib-contained'} 0..$#ARGV;
    die 'missing local library' unless defined $index;
    my $library="$ARGV[$index+1]/lib/perl5";
    make_path($library);
    open my $marker,'>',"$library/installed" or die $!;
    close $marker;
} elsif ($command eq 'cpanm') {
    die 'cpanm must use the selected Perl';
} elsif ($command eq 'git') {
    print((grep {$_ eq '*.pl'} @ARGV) ? "probe.pl\0" : "probe.js\0");
} elsif ($command eq 'go' || $command eq 'node' || $command eq 'prove' || $command eq 'shfmt' || $command eq 'swiftc' || $command eq 'perl') {
    die 'Perl dependencies unavailable to checks' unless -f "$ENV{PERL5LIB}/installed";
}
PERL

sub run_ci {
    my ($name,$actions,$fail)=@_;
    my $tmp=scratch();
    my $project="$tmp/project with spaces";
    my $script=copy_file(root()."/ci/$name.sh","$project/ci/$name.sh");
    my $commands="$tmp/commands";
    write_text("$commands/$_","#!$^X\n$stub",0755) for qw(npm brew perl cpanm go node prove git shfmt swiftc);
    write_text("$project/$_",'') for qw(cpanfile probe.js probe.pl src/tests/probe.test.cjs tests/probe.t);
    my %env=(%ENV,PATH=>"$commands:/usr/bin:/bin",CI_PERL_LOG=>"$tmp/log",CI_PERL_FAIL=>$fail,
        NODE_PATH=>'/old/node',PERL5LIB=>'/old/perl',PERL_CPANM_HOME=>'/old/cpanm',RUNNER_TEMP=>"$tmp/runner");
    delete $env{GITHUB_ACTIONS};
    $env{GITHUB_ACTIONS}='true' if $actions;
    my $result=run_cmd(['/bin/sh',$script],cwd=>$tmp,env=>\%env);
    return ($result,json_lines("$tmp/log"),$project,$commands);
}

for my $name (qw(lint web)) {
    for my $actions (0,1) {
        my $mode=$actions ? 'Actions' : 'local';
        subtest "$name $mode installs dependencies before checks" => sub {
            my ($result,$events,$project,$commands)=run_ci($name,$actions,0);
            is($result->{code},0,$result->{err});
            my @brew=grep {$_->{command} eq 'brew'} @$events;
            is(scalar @brew,$actions,'Homebrew is only used in Actions');
            my ($install)=grep {$_->{command} eq 'perl' && $_->{args}[0] eq "$commands/cpanm"} @$events;
            ok($install,'cpanm runs through the selected Perl');
            my $library="$project/.build/perl-v5.99.7";
            is_deeply($install->{args},["$commands/cpanm",'--notest','--local-lib-contained',$library,'--installdeps','.'],'install declared dependencies without tests');
            is($install->{cwd},$project,'installation runs from repository root');
            my @checks=grep {$_->{command}=~/\A(?:go|node|prove|shfmt|swiftc)\z/ || ($_->{command} eq 'perl' && grep {$_ eq '-c'} @{$_->{args}})} @$events;
            is_deeply([map {$_->{command}} @checks],$name eq 'lint' ? [qw(go node shfmt swiftc perl)] : [qw(node prove)],'expected checks run');
            for my $event ($install,@checks) {
                is_deeply([@{$event->{env}}{qw(NODE_PATH PERL_CPANM_HOME PERL5LIB)}],
                    ["$project/node_modules","$project/.build/cpanm","$library/lib/perl5"],"$event->{command} uses repository dependencies");
                is((split /:/,$event->{env}{PATH})[0],"$library/bin","$event->{command} uses installed executables");
            }
        };
        subtest "$name $mode stops when dependency installation fails" => sub {
            my ($result,$events)=run_ci($name,$actions,1);
            is($result->{code},23,'installer failure is preserved');
            is($events->[-1]{command},'perl','installer is last command');
            like($events->[-1]{args}[0],qr{/cpanm\z},'checks never start');
        };
    }
}
done_testing;
