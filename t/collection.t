#!perl -Tw

use strict;
use warnings;

use Test::More qw(no_plan);

use_ok('Data::Beacon::Collection');
use_ok('Data::Beacon::Collection::DBI');

eval { 
    use DBD::SQLite;
    use File::Temp qw(tempfile);
}; 
if ( $@ ) {
    diag("skipping test of Data::Beacon::Collection: $@");
    exit;
}

my ($fh, $filename) = tempfile( EXLOCK => 0 );

my $col = eval { Data::Beacon::Collection->new( dbi => "foobar" ); };
ok ( $@ && !$col );

$col = Data::Beacon::Collection->new( dbi => "SQLite:dbname=$filename" );
ok( $col->connected );
is_deeply( [ $col->list ], [ ], 'empty list' );

is( $col->get('foo'), undef );

use_ok('Data::Beacon');
my $b1 = beacon('t/beacon2.txt');
my $b2 = $col->insert( 'foo', $b1 );

is_deeply( [ $col->list ], ['foo'] );
is( $b2->count, $b1->count, 'same count' );
is( $b2->metafields, $b1->metafields, 'same meta' );

# $col->get('foo')->query('a');

# ...
ok ( ! $col->remove('bar') );
ok ( ! $col->lasterror );

ok( $col->remove('foo'), 'remove' );
is( $col->get('foo'), undef );
