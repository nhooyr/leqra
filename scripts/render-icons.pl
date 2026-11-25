#!/usr/bin/env perl
use strict;
use warnings;
use Cwd            qw(abs_path);
use File::Basename qw(dirname basename);
use File::Copy     qw(copy);
use File::Path     qw(make_path);
use File::Temp     qw(tempdir);
use Getopt::Long   qw(GetOptions);
use XML::Parser;

# Render directly from SVG with Inkscape; preview exports never alter native icons.
my ( $output_dir, $help );
GetOptions( 'output-dir=s' => \$output_dir, 'h|help' => \$help ) && !@ARGV
  or die "Usage: gen-icons.sh [--output-dir DIR]\n";
if ($help) {
    print "Usage: gen-icons.sh [--output-dir DIR]\nRender app icons directly from SVG using Inkscape.\n";
    exit;
}
my ($inkscape) = grep { -f $_ && -x $_ } map { "$_/inkscape" } split /:/, $ENV{PATH};
die "Inkscape is required to render the vector artwork.\n"
  unless defined $inkscape;
my $root = dirname( dirname( abs_path(__FILE__) ) );

sub read_text {
    open my $f, '<', $_[0] or die "$_[0]: $!\n";
    local $/;
    return <$f>;
}
my ($version) = read_text("$root/src/main.go") =~ /\bversion\s*=\s*"([^"]+)"/;
die "No version in src/main.go\n" unless defined $version;
my $assets = "$root/src/web/assets/$version";
my $source = "$assets/favicon.svg";
my $svg    = read_text($source);
my $tree   = XML::Parser->new( Style => 'Tree' )->parse($svg);
my @box    = split /\s+/, $tree->[1][0]{viewBox};
die "favicon.svg must have a four-value viewBox\n" unless @box == 4;
my $opaque = $svg;
my $background =
  qq{<rect id="icon-background" x="$box[0]" y="$box[1]" width="$box[2]" height="$box[3]" fill="#111619"/>};
$opaque =~ s{(<svg\b[^>]*>)}{$1$background} or die "No SVG root element\n";
my $output = $output_dir // $assets;
make_path($output);
$output = abs_path($output);
my $temporary     = tempdir( 'leqra-icons-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my $opaque_source = "$temporary/opaque.svg";
open my $file, '>', $opaque_source or die "$opaque_source: $!\n";
print {$file} $opaque;
close $file or die "$opaque_source: $!\n";

sub render {
    my ( $vector, $destination, $size, $rgb ) = @_;
    system(
        $inkscape,                        $vector,
        '--export-area-page',             '--export-type=png',
        "--export-filename=$destination", "--export-width=$size",
        "--export-height=$size",          '--export-background-opacity=0',
        '--export-png-color-mode=' . ( $rgb ? 'RGB_8' : 'RGBA_8' )
    ) == 0 or die "Inkscape failed for $destination\n";
    print basename($destination) . ": ${size}x${size} directly from SVG\n";
}
render( $source,        "$output/icon-$_.png",              $_ ) for ( 192, 512, 1024 );
render( $source,        "$output/favicon-256.png",          256 );
render( $opaque_source, "$output/apple-touch-icon.png",     180 );
render( $opaque_source, "$output/apple-touch-icon-512.png", 512 );
unless ( defined $output_dir ) {
    render( $opaque_source, "$root/ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon.png", 1024,      1 );
    render( $opaque_source, "$root/ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon-mac-$_.png", $_, 1 )
      for ( 16, 32, 64, 128, 256, 512 );
    copy( "$output/icon-1024.png", "$root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" )
      or die "copy Android icon: $!\n";
    for my $brand (
        "$root/ios/leqra/Assets.xcassets/BrandIcon.imageset/brand-icon.png",
        "$root/android/app/src/main/res/drawable-nodpi/brand_icon.png"
      )
    {
        make_path( dirname($brand) );
        copy( "$output/icon-192.png", $brand ) or die "copy $brand: $!\n";
    }
    print "Native iOS, macOS and Android icons synchronized\n";
}
