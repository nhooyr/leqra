use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
my $wrapper = 'android/gradle/wrapper/gradle-wrapper.jar';
subtest 'wrapper jar contains its launcher' => sub {
    ok( -f root() . "/$wrapper", 'launcher is present' );
    my $list = run_cmd( [ 'unzip', '-Z1', root() . "/$wrapper" ] );
    is( $list->{code}, 0, 'jar opens' );
    like( $list->{out}, qr{^org/gradle/wrapper/GradleWrapperMain\.class$}m, 'main class' );
    my $manifest = run_cmd( [ 'unzip', '-p', root() . "/$wrapper", 'META-INF/MANIFEST.MF' ] );
    like( $manifest->{out}, qr/Main-Class: org\.gradle\.wrapper\.GradleWrapperMain/, 'manifest launcher' );
    is( run_cmd( [ 'unzip', '-t', root() . "/$wrapper" ] )->{code}, 0, 'all entries pass CRC' );
};
subtest 'wrapper jar is not ignored' => sub {
    is( run_cmd( [ 'git', 'check-ignore', '--no-index', '--quiet', $wrapper ], cwd => root() )->{code},
        1, 'included in Git' );
};
done_testing;
