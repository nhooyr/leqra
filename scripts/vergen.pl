#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Cwd            qw(abs_path);
use File::Basename qw(dirname basename);
use File::Temp     qw(tempfile);

# Synchronize release markers without changing artwork or historical documents.
my $VERSION           = qr/v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?/;
my $GENERATED_VERSION = qr/v?[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?/;

sub read_text {
    my ($path) = @_;
    open my $file, '<:encoding(UTF-8)', $path or die "$path: $!\n";
    local $/;
    return <$file>;
}

sub replace {
    my ( $text, $pattern, $replacement, $expected, $path ) = @_;
    my $count = 0 + ( $text =~ s/$pattern/$replacement->($1, $2)/ge );
    die "Expected $expected version marker(s) in $path; found $count.\n"
      if $count != $expected;
    return $text;
}

sub write_atomic {
    my ( $path, $text )      = @_;
    my ( $file, $temporary ) = tempfile(
        '.' . basename($path) . '.XXXXXX',
        DIR    => dirname($path),
        UNLINK => 1
    );
    binmode $file, ':encoding(UTF-8)';
    print {$file} $text or die "$temporary: $!\n";
    close $file         or die "$temporary: $!\n";
    chmod( ( stat($path) )[2] & 07777, $temporary )
      or die "chmod $temporary: $!\n";
    rename $temporary, $path or die "rename $temporary: $!\n";
}

sub synchronize {
    my ($root)   = @_;
    my $main     = read_text("$root/src/main.go");
    my @versions = $main =~ /^\s*version\s*=\s*"($VERSION)"/mg;
    die "src/main.go must declare exactly one vX.Y.Z version, optionally with a -suffix.\n"
      unless @versions == 1;
    my $version       = $versions[0];
    my $index         = "$root/src/web/index.html";
    my $original_html = read_text($index);
    my $html          = $original_html;
    @versions = $html =~ /src="assets\/($VERSION)\/game\.js"/g;
    die "index.html must reference exactly one versioned game.js.\n"
      unless @versions == 1;
    my $previous    = "$root/src/web/assets/$versions[0]";
    my $destination = "$root/src/web/assets/$version";
    die 'Both '
      . basename($previous) . ' and '
      . basename($destination)
      . " exist; refusing to overwrite assets.\n"
      if $previous ne $destination && -e $previous && -e $destination;
    my $source = -d $previous ? $previous : $destination;
    die "The browser asset directory is missing: $previous.\n"
      unless -d $source;
    my @updates;
    my $stage = sub {
        my ( $path, $pattern, $replacement, $target ) = @_;
        my $original = read_text($path);
        ( my $label = $path ) =~ s/^\Q$root\E\///;
        my $updated = replace( $original, $pattern, $replacement, 1, $label );
        push @updates, [ $target // $path, $updated ] if $original ne $updated;
    };
    $html =~ s{assets/$VERSION/}{assets/$version/}g;
    $html = replace(
        $html,
        qr{(<meta\s+name="leqra-version"\s+content=")$VERSION(")},
        sub { $_[0] . $version . $_[1] },
        1, 'src/web/index.html'
    );
    push @updates, [ $index, $html ] if $html ne $original_html;
    for my $entry ( [ 'game.js', 'GAME_VERSION' ], [ 'pwa.js', 'VERSION' ], [ 'sw.js', 'VERSION' ] ) {
        my ( $name, $marker ) = @$entry;
        $stage->(
            "$source/$name",
            qr{(\bconst\s+$marker\s*=\s*['"])$GENERATED_VERSION(['"])},
            sub { $_[0] . $version . $_[1] },
            "$destination/$name"
        );
    }
    for my $name ( 'polish49_test.go', 'polish410_test.go' ) {
        $stage->(
            "$root/src/$name",
            qr{if version != "$GENERATED_VERSION"},
            sub { "if version != \"$version\"" }
        );
    }
    my $protocol = "$root/docs/PROTOCOL.md";
    my $original = read_text($protocol);
    my ( $current, $history ) = split /(?=\n# )/, $original, 2;
    $history //= '';
    $current = replace(
        $current,
        qr{^(# leqra )$VERSION(?= — current game protocol)}m,
        sub { $_[0] . $version },
        1, 'docs/PROTOCOL.md title'
    );
    for my $type ( 'server_hello', 'client_hello', 'join', 'welcome' ) {
        $current = replace(
            $current,
            qr{^(\s*\{\s*"type"\s*:\s*"$type",[^{}\n]*?"version"\s*:\s*")$GENERATED_VERSION(?=")}m,
            sub { $_[0] . $version },
            1, "docs/PROTOCOL.md current $type example"
        );
    }
    push @updates, [ $protocol, $current . $history ]
      if $current . $history ne $original;
    my $moved = $source ne $destination;
    rename $source, $destination or die "rename $source: $!\n" if $moved;
    write_atomic(@$_) for @updates;
    print( ( $moved || @updates ? 'Generated' : 'Already generated' ) . " leqra $version.\n" );
}
if ( @ARGV == 1 && $ARGV[0] =~ /\A(?:--help|-h)\z/ ) {
    print "Usage: gen-version.sh\nSynchronize release files after editing version in src/main.go.\n";
    exit;
}
die "Usage: gen-version.sh\n" if @ARGV;
synchronize( dirname( dirname( abs_path(__FILE__) ) ) );
