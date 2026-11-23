package LeqraTest;
use strict;
use warnings;
use Exporter 'import';
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir tempfile);
use File::Copy qw(copy);
use Encode qw(encode decode);
use JSON::PP;
use IPC::Open3;
use IO::Select;
use Symbol qw(gensym);
our @EXPORT = qw(root scratch read_text read_bytes write_text write_bytes copy_file run_cmd json_lines make_path);
sub root { abs_path(dirname(__FILE__) . '/..') }
sub scratch { abs_path(tempdir('leqra perl tests XXXXXX', TMPDIR => 1, CLEANUP => 1)) }
sub read_bytes { open my $f, '<:raw', $_[0] or die "$_[0]: $!"; local $/; return <$f>; }
sub read_text { decode('UTF-8', read_bytes($_[0])) }
sub write_bytes { my ($path, $data, $mode) = @_; make_path(dirname($path)); open my $f, '>:raw', $path or die "$path: $!"; print {$f} $data; close $f or die "$path: $!"; chmod $mode, $path if defined $mode; return $path; }
sub write_text { my ($path, $text, $mode) = @_; write_bytes($path, encode('UTF-8', $text), $mode) }
sub copy_file { my ($a, $b) = @_; make_path(dirname($b)); copy($a, $b) or die "copy $a: $!"; chmod((stat($a))[2] & 07777, $b); return $b; }
sub run_cmd {
    my ($command, %options) = @_;
    local %ENV = $options{env} ? %{$options{env}} : %ENV;
    my $before = getcwd();
    chdir $options{cwd} or die "chdir: $!" if $options{cwd};
    my ($input, $output, $error) = (gensym(), gensym(), gensym());
    my $pid = open3($input, $output, $error, '/bin/sh', '-c', 'exec "$@"', 'sh', @$command);
    chdir $before or die "restore cwd: $!";
    print {$input} $options{input} // '';
    close $input;
    my $selector = IO::Select->new($output, $error);
    my %data = (fileno($output) => '', fileno($error) => '');
    while (my @ready = $selector->can_read()) {
        for my $handle (@ready) {
            my $length = sysread($handle, my $chunk, 65536);
            defined($length) or die "read: $!";
            if ($length) { $data{fileno($handle)} .= $chunk; }
            else { $selector->remove($handle); }
        }
    }
    waitpid($pid, 0);
    return {code => $? >> 8, signal => $? & 127, out => decode('UTF-8',$data{fileno($output)}), err => decode('UTF-8',$data{fileno($error)})};
}
sub json_lines { [map { decode_json($_) } grep { length } split /\n/, read_bytes($_[0])] }
1;
