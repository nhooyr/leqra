use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use JSON::PP;
use Cwd qw(abs_path);
use File::Spec;
sub fixture {
    my $tmp=scratch(); my $project="$tmp/project with spaces";
    my $scripts="$project/scripts"; make_path($scripts,"$tmp/unrelated working directory");
    write_text("$project/src/main.go","const (\n version = \"v1.2.3-dev\"\n)\n");
    opendir my $dir,root().'/scripts' or die $!;
    copy_file(root()."/scripts/$_","$scripts/$_") for grep {-f root()."/scripts/$_"} readdir $dir;
    for my $name ('perl','go') { write_text("$tmp/mock commands/$name",<<'PERL',0755); }
#!/usr/bin/perl
use JSON::PP; use Cwd qw(getcwd); use File::Basename qw(basename);
local $/; print encode_json({command=>basename($0),args=>\@ARGV,cwd=>getcwd(),stdin=><STDIN>}),"\n";
print STDERR "mock stderr\n"; exit($ENV{MOCK_EXIT}//0);
PERL
    return ($tmp,$project,$scripts,"$tmp/unrelated working directory");
}
sub invocation {
    my ($tmp,$scripts,$caller,$name,$form)=@_;
    my %env=(%ENV,PATH=>"$tmp/mock commands:$ENV{PATH}");
    my $command;
    if ($form eq 'absolute') { $command="$scripts/$name"; }
    elsif ($form eq 'relative') { $command=File::Spec->abs2rel("$scripts/$name",$caller); }
    else { my $entry=$form eq 'path' ? $scripts : File::Spec->abs2rel($scripts,$caller); $env{PATH}="$entry:$env{PATH}"; $command=$name; }
    return ($command,\%env);
}
sub resolved { my ($caller,$path)=@_; my @parts; for (split m{/},File::Spec->rel2abs($path,$caller)) { next if !length || $_ eq '.'; $_ eq '..' ? pop(@parts) : push(@parts,$_); } return '/' . join('/',@parts); }
subtest 'generators preserve caller arguments status and script paths' => sub {
    my ($tmp,$project,$scripts,$caller)=fixture();
    my @arguments=('output folder/file.html','','quoted "value"','two words');
    for my $name ('gen-icons.sh','gen-version.sh') { for my $form (qw(absolute relative path relative_path)) { for my $status (0,37) {
        my ($command,$env)=invocation($tmp,$scripts,$caller,$name,$form); $env->{MOCK_EXIT}=$status;
        my $r=run_cmd([$command,@arguments],cwd=>$caller,env=>$env); is($r->{code},$status,"$name $form exit");
        my $record=decode_json($r->{out}); is($record->{command},'perl','Perl interpreter');
        my $implementation=$name eq 'gen-icons.sh' ? 'render-icons.pl' : 'vergen.pl';
        is(abs_path(resolved($caller,$record->{args}[0])),abs_path("$scripts/$implementation"),'implementation path');
        is_deeply([@{$record->{args}}[1..$#{$record->{args}}]],\@arguments,'arguments');
        is($record->{cwd},$caller,'caller cwd'); is($r->{err},"mock stderr\n",'stderr');
    } } }
};
subtest 'featured graphic preserves paths arguments and status' => sub {
    my ($tmp,$project,$scripts,$caller)=fixture();
    for my $form (qw(absolute relative path relative_path)) { for my $status (0,37) {
        my ($command,$env)=invocation($tmp,$scripts,$caller,'gen-featured-android.sh',$form); $env->{MOCK_EXIT}=$status;
        my @arguments=('-input','my screenshot.png','-center','700,520');
        my $r=run_cmd([$command,@arguments],cwd=>$caller,env=>$env); is($r->{code},$status,'exit');
        my $record=decode_json($r->{out}); is($record->{command},'go','Go renderer'); my $args=$record->{args};
        is($args->[0],'run','run'); like(resolved($caller,$args->[1]),qr{\Q$scripts\E/featured-graphic/main\.go$},'renderer path');
        is($args->[2],'-input','input flag'); is(resolved($caller,$args->[3]),"$project/docs/showcase.png",'default input');
        is($args->[4],'-output','output flag'); is(resolved($caller,$args->[5]),"$project/docs/showcase-featured-android.png",'default output');
        is_deeply([@$args[6..$#$args]],\@arguments,'forwarded arguments'); is($record->{cwd},$caller,'cwd'); is($r->{err},"mock stderr\n",'stderr');
    } }
};
subtest 'version query works from unrelated directory and PATH' => sub {
    my ($tmp,$project,$scripts,$caller)=fixture();
    for my $form (qw(absolute relative path relative_path)) {
        my ($command,$env)=invocation($tmp,$scripts,$caller,'version.sh',$form);
        my $r=run_cmd([$command],cwd=>$caller,env=>$env); is($r->{code},0,'status'); is($r->{out},"v1.2.3-dev\n",'version'); is($r->{err},'','stderr');
    }
};
done_testing;
