use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use File::Find;
use Time::HiRes ();
my $history =
"# Historical v1.2.3 protocol notes\nHistorical v1.2.3 content stays unchanged.\n```json\n{\"type\":\"server_hello\",\"version\":\"1.2.3\",\"protocol\":7}\n{\"type\":\"join\",\"version\":\"1.2.3\",\"protocol\":7}\n```\n";
my $icon = "\x89PNG\r\n\x1a\n\x00unchanged icon bytes\xff";

sub fixture {
    my $tmp     = scratch();
    my $project = "$tmp/project with spaces";
    my $caller  = "$tmp/another directory";
    make_path($caller);
    my %files = (
        'src/main.go'        => "const (\n version = \"v1.2.4\"\n protocolVersion = 7\n)\n",
        'src/web/index.html' =>
"<meta name=\"leqra-version\" content=\"v1.2.3\">\n<script src=\"assets/v1.2.3/game.js\"></script>\n<link href=\"assets/v1.2.3/style.css\">\n",
        'src/web/assets/v1.2.3/game.js'   => "const GAME_VERSION='1.2.3';\nconst GAME_PROTOCOL=7;\n",
        'src/web/assets/v1.2.3/pwa.js'    => "const VERSION = 'v1.2.3';\n",
        'src/web/assets/v1.2.3/sw.js'     => "const VERSION = 'v1.2.3';\n",
        'src/web/assets/v1.2.3/style.css' => "body{color:white}\n",
        'src/polish49_test.go'            => "if version != \"1.2.3\" {\n}\n",
        'src/polish410_test.go'           => "if version != \"1.2.3\" {\n}\n",
        'docs/PROTOCOL.md'                =>
"# leqra v1.2.3 — current game protocol (protocol 7)\n\nThe network protocol epoch is **7**.\n\n```json\n{\"type\":\"server_hello\",\"version\":\"1.2.3\",\"protocol\":7}\n{\"type\":\"client_hello\",\"version\":\"1.2.3\",\"protocol\":7}\n```\n\nRelease v1.2.3 introduced this behavior.\n\n## Infinity\n\n```json\n{\"type\":\"join\",\"version\":\"1.2.3\",\"protocol\":7,\"code\":\"FRIENDS\"}\n{\"type\":\"welcome\",\"protocol\":7,\"version\":\"v1.2.3\",\"id\":0}\n```\n\n$history",
        'README.md'            => "Do not edit this v1.2.3 README.\n",
        'docs/releases/old.md' => "Historical v1.2.3 release.\n"
    );
    write_text( "$project/$_", $files{$_} ) for keys %files;
    copy_file( root() . "/scripts/$_", "$project/scripts/$_" )
      for ( 'gen-version.sh', 'vergen.pl' );
    write_bytes( "$project/src/web/assets/v1.2.3/icon.png", $icon );
    chmod 0640, "$project/src/web/assets/v1.2.3/game.js";
    return ( $project, $caller );
}

sub run_script {
    my ( $project, $caller ) = @_;
    run_cmd( ["$project/scripts/gen-version.sh"], cwd => $caller );
}

sub snapshot {
    my ( $project, $timestamps ) = @_;
    my %snapshot;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                ( my $name = $path ) =~ s/^\Q$project\E\///;
                $snapshot{$name} =
                  $timestamps
                  ? ( Time::HiRes::stat($path) )[9]
                  : [ read_bytes($path), ( stat($path) )[2] ]
                  if $timestamps || -f $path;
            }
        },
        $project
    );
    return \%snapshot;
}

sub verify_version {
    my ( $project, $version ) = @_;
    my $assets = "$project/src/web/assets/$version";
    is( read_bytes("$assets/icon.png"), $icon, 'icon bytes' );
    for my $entry ( [ 'game.js', 'GAME_VERSION' ], [ 'pwa.js', 'VERSION' ], [ 'sw.js', 'VERSION' ] ) {
        like(
            read_text("$assets/$entry->[0]"),
            qr/\Q$entry->[1]\E\s*=\s*['"]\Q$version\E['"]/,
            'asset version'
        );
    }
    my $index = read_text("$project/src/web/index.html");
    like( $index, qr/content="\Q$version\E"/,       'HTML meta' );
    like( $index, qr{assets/\Q$version\E/game\.js}, 'HTML script' );
    my $protocol = read_text("$project/docs/PROTOCOL.md");
    like( $protocol, qr/^# leqra \Q$version\E — current game protocol/,     'protocol title' );
    like( $protocol, qr/"type":"$_","version":"\Q$version\E","protocol":7/, 'protocol packet' )
      for ( 'server_hello', 'client_hello', 'join' );
    like( $protocol, qr/"type":"welcome","protocol":7,"version":"\Q$version\E"/, 'welcome packet' );
    like( $protocol, qr/\Q$history\E\z/,                                         'history preserved' );
}
subtest 'sync from another directory preserves icons modes and history' => sub {
    my ( $project, $caller ) = fixture();
    my %untouched =
      map { $_ => read_bytes("$project/$_") } ( 'README.md', 'docs/releases/old.md', 'src/main.go' );
    my $r = run_script( $project, $caller );
    is( $r->{code}, 0, $r->{err} );
    like( $r->{out}, qr/Generated leqra v1\.2\.4/, 'generated' );
    ok( !-e "$project/src/web/assets/v1.2.3", 'old directory moved' );
    is( ( stat("$project/src/web/assets/v1.2.4/game.js") )[2] & 0777, 0640, 'mode preserved' );
    is(
        read_text("$project/src/web/assets/v1.2.4/game.js"),
        "const GAME_VERSION='v1.2.4';\nconst GAME_PROTOCOL=7;\n",
        'game marker only'
    );
    is( read_bytes("$project/$_"), $untouched{$_}, "$_ untouched" )
      for keys %untouched;
    unlike( read_text("$project/src/web/index.html"), qr/1\.2\.3/, 'old HTML references gone' );
    verify_version( $project, 'v1.2.4' );
    like(
        read_text("$project/docs/PROTOCOL.md"),
        qr/Release v1\.2\.3 introduced this behavior\./,
        'historical prose'
    );
    like( read_text("$project/src/$_"), qr/version != "v1\.2\.4"/, 'Go marker' )
      for ( 'polish49_test.go', 'polish410_test.go' );
};
subtest 'suffix transitions keep every marker synchronized' => sub {
    my ( $project, $caller ) = fixture();
    my $previous = 'v1.2.3';
    for my $version ( 'v1.2.4-dev', 'v1.2.4-rc.2', 'v1.2.4' ) {
        write_text( "$project/src/main.go", "const (\n version = \"$version\"\n protocolVersion = 7\n)\n" );
        my $r = run_script( $project, $caller );
        is( $r->{code}, 0, $r->{err} );
        like( $r->{out}, qr/Generated leqra \Q$version\E\./, 'generated' );
        ok( !-e "$project/src/web/assets/$previous", 'previous bundle moved' );
        verify_version( $project, $version );
        my $before = snapshot( $project, 1 );
        is( run_script( $project, $caller )->{code}, 0, 'repeat succeeds' );
        is_deeply( snapshot( $project, 1 ), $before, 'repeat timestamps unchanged' );
        $previous = $version;
    }
};
subtest 'repeating sync does not rewrite files' => sub {
    my ( $project, $caller ) = fixture();
    is( run_script( $project, $caller )->{code}, 0, 'initial succeeds' );
    my $before = snapshot( $project, 1 );
    my $r      = run_script( $project, $caller );
    is( $r->{code}, 0, $r->{err} );
    like( $r->{out}, qr/Already generated/, 'idempotent' );
    is_deeply( snapshot( $project, 1 ), $before, 'timestamps unchanged' );
};
subtest 'preserves formatted multiline markers' => sub {
    my ( $project, $caller ) = fixture();
    for my $entry ( [ 'game.js', 'GAME_VERSION', '' ], [ 'pwa.js', 'VERSION', 'v' ],
        [ 'sw.js', 'VERSION', 'v' ] )
    {
        write_text( "$project/src/web/assets/v1.2.3/$entry->[0]",
            "  const $entry->[1] = \"$entry->[2]1.2.3\"\n" );
    }
    my $index = read_text("$project/src/web/index.html");
    $index =~
      s/<meta name="leqra-version" content="v1.2.3">/<meta\n  name="leqra-version"\n  content="v1.2.3" \/>/;
    write_text( "$project/src/web/index.html", $index );
    my $r = run_script( $project, $caller );
    is( $r->{code}, 0, $r->{err} );
    for my $entry ( [ 'game.js', 'GAME_VERSION' ], [ 'pwa.js', 'VERSION' ], [ 'sw.js', 'VERSION' ] ) {
        is(
            read_text("$project/src/web/assets/v1.2.4/$entry->[0]"),
            "  const $entry->[1] = \"v1.2.4\"\n",
            'format preserved'
        );
    }
    like( read_text("$project/src/web/index.html"), qr/content="v1\.2\.4" \/>/, 'meta format' );
};
for my $case (
    [
        'existing destination fails before any change',
        sub {
            my ($p) = @_;
            write_text( "$p/src/web/assets/v1.2.4/keep.txt", 'Do not overwrite.' );
        },
        qr/refusing to overwrite/
    ],
    [
        'missing final marker fails before any change',
        sub {
            my ($p) = @_;
            my $text = read_text("$p/docs/PROTOCOL.md");
            $text =~
              s/"join","version":"1.2.3","protocol":7,"code"/"join","version":"missing","protocol":7,"code"/;
            write_text( "$p/docs/PROTOCOL.md", $text );
        },
        qr/PROTOCOL.md current join example/
    ],
    [
        'duplicate marker fails before any change',
        sub {
            my ($p) = @_;
            my $path = "$p/src/web/assets/v1.2.3/game.js";
            write_text( $path, read_text($path) . "const GAME_VERSION='1.2.3';\n" );
        },
        qr/found 2/
    ]
  )
{
    subtest $case->[0] => sub {
        my ( $p, $c ) = fixture();
        $case->[1]->($p);
        my $before = snapshot($p);
        my $r      = run_script( $p, $c );
        isnt( $r->{code}, 0, 'fails' );
        like( $r->{err}, $case->[2], 'reason' );
        is_deeply( snapshot($p), $before, 'unchanged' );
    };
}
subtest 'invalid versions fail without changes' => sub {
    my ( $p, $c ) = fixture();
    for my $version ( '../../outside', '1.2.4', 'v1.2', 'v1.2.4-', 'v1.2.4-dev/other' ) {
        write_text( "$p/src/main.go", "const (\n version = \"$version\"\n)\n" );
        my $before = snapshot($p);
        my $r      = run_script( $p, $c );
        isnt( $r->{code}, 0, 'fails' );
        like( $r->{err}, qr/vX\.Y\.Z/, 'reason' );
        is_deeply( snapshot($p), $before, 'unchanged' );
    }
};
subtest 'rerun finishes previously moved directory' => sub {
    my ( $p, $c ) = fixture();
    rename "$p/src/web/assets/v1.2.3", "$p/src/web/assets/v1.2.4" or die $!;
    my $r = run_script( $p, $c );
    is( $r->{code}, 0, $r->{err} );
    like( read_text("$p/src/web/index.html"), qr{assets/v1\.2\.4/game\.js}, 'HTML updated' );
    is( read_bytes("$p/src/web/assets/v1.2.4/icon.png"), $icon, 'icon intact' );
};
subtest 'repairs stale constants with already-current HTML' => sub {
    my ( $p, $c ) = fixture();
    is( run_script( $p, $c )->{code}, 0, 'first sync' );
    write_text( "$p/src/web/assets/v1.2.4/pwa.js", "const VERSION = 'v1.2.3';\n" );
    my $r = run_script( $p, $c );
    is( $r->{code},                                   0,                             $r->{err} );
    is( read_text("$p/src/web/assets/v1.2.4/pwa.js"), "const VERSION = 'v1.2.4';\n", 'repaired' );
};
done_testing;
