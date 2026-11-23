#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Digest::SHA qw(sha256_hex);
use JSON::PP;

# macOS getattrlist/setattrlist retain exact nanoseconds used by Swift build records.
sub modification_time {
    my ($path) = @_;
    my $attrs = pack('S2L5', 5, 0, 0x00000400, 0, 0, 0, 0);
    my $buffer = "\0" x 20;
    syscall(220, $path, $attrs, $buffer, length($buffer), 0) == 0 or die "getattrlist $path: $!\n";
    my (undef, $seconds, $nanoseconds) = unpack('Lq2', $buffer);
    return $seconds * 1_000_000_000 + $nanoseconds;
}
sub set_modification_time {
    my ($path, $nanoseconds) = @_;
    my $attrs = pack('S2L5', 5, 0, 0x00000400, 0, 0, 0, 0);
    use integer;
    my $buffer = pack('q2', $nanoseconds / 1_000_000_000, $nanoseconds % 1_000_000_000);
    syscall(221, $path, $attrs, $buffer, length($buffer), 0) == 0 or die "setattrlist $path: $!\n";
}
sub inputs {
    my ($root) = @_;
    open my $git, '-|', 'git', '-C', $root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'ios', 'scripts/ios-version.sh', 'scripts/version.sh', 'src/main.go' or die "git: $!\n";
    local $/;
    my %names = map { $_ => 1 } split /\0/, <$git>;
    close $git or die "git ls-files failed\n";
    return grep { -f "$root/$_" && !-l "$root/$_" } sort keys %names;
}
sub digest {
    open my $file, '<:raw', $_[0] or die "$_[0]: $!\n";
    return Digest::SHA->new(256)->addfile($file)->hexdigest;
}
sub save {
    my ($root, $manifest) = @_;
    my %records = map { $_ => {sha256 => digest("$root/$_"), mtime_ns => modification_time("$root/$_")} } inputs($root);
    make_path(dirname($manifest));
    open my $file, '>', $manifest or die "$manifest: $!\n";
    print {$file} JSON::PP->new->canonical->encode(\%records), "\n";
    close $file or die "$manifest: $!\n";
}
sub restore {
    my ($root, $manifest) = @_;
    return unless -e $manifest;
    open my $file, '<', $manifest or die "$manifest: $!\n";
    local $/;
    my $records = decode_json(<$file>);
    my $restored = 0;
    for my $name (inputs($root)) {
        my $record = $records->{$name};
        next unless $record && $record->{sha256} eq digest("$root/$name");
        set_modification_time("$root/$name", $record->{mtime_ns});
        ++$restored;
    }
    print "Restored timestamps for $restored unchanged iOS build inputs.\n";
}
unless (caller) {
    if (@ARGV == 1 && $ARGV[0] =~ /\A(?:--help|-h)\z/) {
        print "Usage: ios-cache.pl restore|save MANIFEST\nKeep unchanged iOS input timestamps aligned with cached Swift build records.\n";
        exit;
    }
    @ARGV == 2 && $ARGV[0] =~ /\A(?:restore|save)\z/ or die "Usage: ios-cache.pl restore|save MANIFEST\n";
    my ($action, $manifest) = @ARGV;
    my $root = dirname(dirname(abs_path(__FILE__)));
    $action eq 'save' ? save($root, $manifest) : restore($root, $manifest);
}
1;
