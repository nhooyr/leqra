use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;

my $library = root() . '/src/tests/lib';
my $fixture = 'my $server = Leqra::HTTPFixture->new(sub { HTTP::Response->new(200) }); ';
my $failed  = run_cmd(
    [ $^X, "-I$library", '-MLeqra::HTTPFixture', '-e', $fixture . 'die "intentional assertion failure\n";' ]
);
isnt( $failed->{code}, 0, 'HTTP fixture cleanup preserves assertion failure status' );
like(
    $failed->{err},
    qr/intentional assertion failure/,
    'HTTP fixture cleanup preserves the failure message'
);
my $exited = run_cmd( [ $^X, "-I$library", '-MLeqra::HTTPFixture', '-e', $fixture . 'exit 7;' ] );
is( $exited->{code}, 7, 'HTTP fixture cleanup preserves explicit exit status' );
my $passed = run_cmd( [ $^X, "-I$library", '-MLeqra::HTTPFixture', '-e', $fixture . '$server->stop;' ] );
is( $passed->{code}, 0, 'successful HTTP fixture cleanup remains successful' );
done_testing;
