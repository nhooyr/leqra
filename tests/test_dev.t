use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
subtest 'browser uses the configured listen address' => sub {
    for my $case (
        [ 'Darwin', {},                                       'http://test.local:8080' ],
        [ 'Darwin', { PORT => '8099' },                       'http://test.local:8099' ],
        [ 'Darwin', { PORT => '8099', ADDR => '[::1]:9020' }, 'http://[::1]:9020' ],
        [ 'Darwin', { ADDR => ':0' },                         undef ],
        [ 'Linux',  {},                                       undef ]
      )
    {
        my ( $system, $settings, $expected ) = @$case;
        my $tmp      = scratch();
        my $project  = "$tmp/project with spaces";
        my $script   = copy_file( root() . '/dev.sh', "$project/dev.sh" );
        my $commands = "$tmp/commands";
        my $log      = "$tmp/log";
        my %stubs    = (
            go =>
              <<'SH', uname => "echo $system", hostname => 'echo test.local', curl => 'printf "probe %s\n" "$4" >> "$TEST_LOG"', open => 'printf "open %s\n" "$3" >> "$TEST_LOG"' );
mkdir -p bin
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$TEST_LOG"' > bin/leqra
chmod +x bin/leqra
SH
        write_text( "$commands/$_", "#!/bin/sh\n$stubs{$_}\n", 0755 )
          for keys %stubs;
        my %env = map { $_ => $ENV{$_} }
          grep { $_ ne 'ADDR' && $_ ne 'PORT' } keys %ENV;
        @env{qw(PATH TEST_LOG)} = ( "$commands:/usr/bin:/bin", $log );
        @env{ keys %$settings } = values %$settings;
        my $r = run_cmd( [ '/bin/sh', $script ], cwd => $tmp, env => \%env );
        is( $r->{code}, 0, $r->{err} );
        my @lines = split /\n/, read_text($log);
        is( shift @lines, '-check-assets', 'asset check' );
        is_deeply(
            [ sort grep { length } @lines ],
            [
                sort defined($expected)
                ? ( "probe $expected", "open $expected" )
                : ()
            ],
            "$system browser selection"
        );
    }
};
done_testing;
