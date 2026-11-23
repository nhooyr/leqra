#!/usr/bin/env perl
use v5.34;
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../src/tests/lib";
use Test::More;
use Encode qw(encode_utf8);
use Leqra::Browser;

ok( value_eq( { a => 1, b => [2] }, { b => [2], a => 1 } ), 'value comparison ignores hash key order' );
ok( !value_eq( [ 1, 2 ], [ 2, 1 ] ),                        'value comparison keeps array order' );
ok( contains_value( 'pilot SPECTATING', 'SPECTATING' ),     'string membership checks a substring' );
ok( contains_value( [ 'a', 'b' ], 'b' ),                    'array membership checks values' );
ok( contains_value( { b => 0 }, 'b' ), 'hash membership checks keys even for false values' );
ok( !contains_value( {}, 'b' ),        'absent key remains absent' );
is_deeply( array_slice( [ 1, 2, 3 ], -2, undef ), [ 2, 3 ], 'negative slices count from end' );
is_deeply(
    transpose_columns( [ [ 1, 2 ], [ 3, 4 ] ] ),
    [ [ 1, 3 ], [ 2, 4 ] ],
    'zip expansion transposes arrays'
);
is_deeply( unique_values( [ 2, 1, 2 ] ), [ 1, 2 ], 'unique values remove duplicates' );
is( array_index( [ 'a', 'b' ], 'b' ), 1, 'array index finds position' );
my $values = [ 'a', 'b' ];
remove_item( $values, 'a' );
is_deeply( $values, ['b'], 'array removal removes the matching item' );
is( mean( [ 1, 2, 3 ] ),      2,   'mean' );
is( stddev( [ 1, 1 ] ),       0,   'population deviation' );
is( median( [ 1, 4, 2, 3 ] ), 2.5, 'median even count' );
ok( Leqra::Browser::_matches( "hello\n world", 'hello world', 0, 1 ),
    'text assertions normalize whitespace' );
ok( !Leqra::Browser::_matches( ' value ', 'value', 0, 0 ), 'attribute/value checks preserve spaces' );
ok( Leqra::Browser::_matches( [ 'a', 'extra', 'b' ], [ 'a', 'b' ], 1, 1 ),
    'contains-text arrays allow intervening elements' );
ok( !Leqra::Browser::_matches( [ 'b', 'a' ], [ 'a', 'b' ], 1, 1 ),
    'contains-text arrays preserve expected order' );
is_deeply(
    query_values('room=one&room=two'),
    { room => [ 'one', 'two' ] },
    'URL queries preserve repeated fields'
);

{

    package TestEvents;
    sub new { bless {}, shift }
    sub on  { $_[0]{listener} = $_[2] }
}
my $events  = [];
my $emitter = TestEvents->new;
capture_event( $emitter, 'pageerror', $events, 'error => String(error)' );
my $file = tied(@$events)->{file};
open my $output, '>>:raw', $file or die $!;
print {$output} encode_utf8( json_text( { message => '💥' } ) . "\n" );
close $output;
is_deeply( $events->[0], { message => '💥' }, 'native event log preserves Unicode data' );
is( scalar(@$events), 1, 'native events become visible without polling a callback bridge' );

{

    package BrokenLocator;
    sub isVisible { die "invalid selector\n" }
}
my $failed = eval {
    expect_locator( bless( {}, 'BrokenLocator' ), 'not_to_be_visible', { timeout => 0 } );
    1;
};
ok( !$failed, 'negative assertions cannot pass when the browser API fails' );
like( $@, qr/Locator assertion/, 'failed assertion produces a diagnostic' );
ok( !truth_value( [] ),  'empty browser array is false' );
ok( !truth_value( {} ),  'empty browser object is false' );
ok( truth_value( [0] ),  'nonempty browser array is true' );
ok( !truth_value(0),     'zero is false' );
ok( !truth_value(undef), 'null is false' );
{

    package TestEvaluation;
    sub new      { bless { value => $_[1] }, $_[0] }
    sub evaluate { return { value => $_[0]{value} } }
}
is( evaluate_js( TestEvaluation->new(0),               '0' ), 0, 'zero survives browser result wrapper' );
is( evaluate_js( TestEvaluation->new(JSON::PP::false), 'false' ),
    JSON::PP::false, 'false survives browser result wrapper' );
ok( !defined( evaluate_js( TestEvaluation->new(undef), 'null' ) ), 'null survives browser result wrapper' );
is_deeply(
    evaluate_js( TestEvaluation->new( [ { a => 1 } ] ), '[{a:1}]' ),
    [ { a => 1 } ],
    'array objects remain data rather than browser handles'
);
done_testing;
