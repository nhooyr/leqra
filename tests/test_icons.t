use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use File::Basename qw(basename);
use XML::Parser;
my $source = <<'SVG';
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<g id="tank"><rect x="20" y="20" width="24" height="24" fill="#ffffff"/></g>
</svg>
SVG

sub opaque {
    my ($svg)   = @_;
    my $tree    = XML::Parser->new( Style => 'Tree' )->parse($svg);
    my $content = $tree->[1];
    my $background;
    for ( my $i = 1 ; $i < @$content ; $i += 2 ) {
        $background = $content->[ $i + 1 ][0]
          if $content->[$i] eq 'rect'
          && ( $content->[ $i + 1 ][0]{id} // '' ) eq 'icon-background';
    }
    ok( $background, 'background is a direct child and unscaled' );
    is( $background->{fill}, '#111619', 'opaque dark background' );
    ok( !exists( $background->{rx} ) && !exists( $background->{ry} ), 'square edges' );
}

sub fixture {
    my $tmp = scratch();
    copy_file( root() . '/scripts/render-icons.pl', "$tmp/scripts/render-icons.pl" );
    write_text( "$tmp/src/main.go", 'const version = "v1.2.3-dev"' );
    my $assets = "$tmp/src/web/assets/v1.2.3-dev";
    write_text( "$assets/favicon.svg", $source );
    my @native = (
        "$tmp/ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "$tmp/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
        "$tmp/ios/leqra/Assets.xcassets/BrandIcon.imageset/brand-icon.png",
        "$tmp/android/app/src/main/res/drawable-nodpi/brand_icon.png"
    );
    write_text( $_, 'original native icon' ) for @native;
    write_text( "$tmp/commands/inkscape", <<'PERL', 0755 );
#!/usr/bin/perl
use strict; use warnings; use JSON::PP;
my @args=@ARGV; open my $f,'<',$args[0] or die $!; my $svg=do{local $/;<$f>}; close $f;
my ($output)=map {/^--export-filename=(.*)$/ ? $1 : ()} @args;
open my $out,'>',$output or die $!; print {$out} $svg; close $out;
open my $log,'>>',$ENV{ICON_EXPORT_LOG} or die $!; print {$log} encode_json({args=>\@args,svg=>$svg,output=>$output}),"\n";
PERL
    return ( $tmp, $assets, \@native );
}
subtest 'preview preserves native icons and transparent artwork' => sub {
    my ( $tmp, $assets, $native ) = fixture();
    my %env = (
        %ENV,
        PATH            => "$tmp/commands:$ENV{PATH}",
        ICON_EXPORT_LOG => "$tmp/exports.jsonl"
    );
    my $r = run_cmd(
        [ $^X, "$tmp/scripts/render-icons.pl", '--output-dir', "$tmp/web previews" ],
        cwd => $tmp,
        env => \%env
    );
    is( $r->{code}, 0, $r->{err} );
    my $exports = json_lines("$tmp/exports.jsonl");
    is( scalar @$exports, 6,                      'six previews' );
    is( read_text($_),    'original native icon', 'native icon preserved' )
      for @$native;
    for my $export (@$exports) {
        basename( $export->{output} ) =~ /^apple-touch/
          ? opaque( $export->{svg} )
          : is( $export->{svg}, $source, 'transparent artwork unchanged' );
    }
};
subtest 'default synchronizes RGB iOS and transparent Android/header artwork' => sub {
    my ( $tmp, $assets, $native ) = fixture();
    my %env = (
        %ENV,
        PATH            => "$tmp/commands:$ENV{PATH}",
        ICON_EXPORT_LOG => "$tmp/exports.jsonl"
    );
    my $r = run_cmd(
        [ $^X, "$tmp/scripts/render-icons.pl" ],
        cwd => $tmp,
        env => \%env
    );
    is( $r->{code}, 0, $r->{err} );
    my $exports = json_lines("$tmp/exports.jsonl");
    is( scalar @$exports, 7, 'seven renders' );
    my ($ios) = grep { $_->{output} eq $native->[0] } @$exports;
    ok( grep( $_ eq '--export-png-color-mode=RGB_8', @{ $ios->{args} } ), 'RGB iOS' );
    ok( grep( $_ eq '--export-width=1024',           @{ $ios->{args} } ), '1024 iOS' );
    opaque( $ios->{svg} );
    is( read_bytes( $native->[1] ), read_bytes("$assets/icon-1024.png"), 'Android uses transparent 1024' );
    is( read_bytes($_),             read_bytes("$assets/icon-192.png"),  'brand uses transparent 192' )
      for @$native[ 2, 3 ];
    is( read_text("$assets/favicon.svg"), $source, 'SVG preserved' );
};
done_testing;
