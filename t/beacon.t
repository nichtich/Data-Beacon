#!perl -Tw

use strict;
use warnings;

use Test::More qw(no_plan);

use_ok('Data::Beacon');

my $r;
my $b = new Data::Beacon();
isa_ok($b,'Data::Beacon');

# meta fields
my %m = $b->meta();
is_deeply( \%m, { 'FORMAT' => 'BEACON' }, 'meta()' );

is_deeply( $b->meta('fOrMaT'), 'BEACON' );
is_deeply( $b->meta('foo'), undef );
is_deeply( $b->meta( {} ), undef );

# not allowed or bad arguments
eval { $b->meta( 'a','b','c' ); }; ok( $@ );
eval { $b->meta( ' format' => '' ); }; ok( $@ );
eval { $b->meta( ' ' => 'x' ); }; ok( $@ );
eval { $b->meta( '~' => 'x' ); }; ok( $@ );
eval { $b->meta( 'prefix' => 'htt' ); }; ok( $@ , 'detect invalid PREFIX');
eval { $b->meta( 'Feed' => 'http://#' ); }; ok( $@ , 'detect invalid FEED');

$b->meta( 'prefix' => 'http://foo.bar' );
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'PREFIX' => 'http://foo.bar' } );
$b->meta( 'prefix' => 'u:' ); # URI prefix
$b->meta( 'prefix' => '' );

eval { $b->meta( 'revisit' => 'Sun 3rd Nov, 1943' ); }; ok( $@ , 'detect invalid REVISIT');
$b->meta( 'REvisit' => '2010-02-31T12:00:01' );
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'REVISIT' => '2010-03-03T12:00:01' } );
$b->meta( 'REVISIT' => '' );

# not tested yet: FEED
is( $b->meta( 'EXAMPLES' ), undef );
$b->meta( 'EXAMPLES', 'foo | bar||doz ' );
is( $b->meta('EXAMPLES'), 'foo|bar|doz', 'EXAMPLES' );
$b->meta( 'EXAMPLES', '|' );
is( $b->meta('EXAMPLES'), undef );
$b->meta( 'EXAMPLES', '' );

$b->meta('foo' => 'bar ', ' X ' => " Y\nZ");
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'FOO' => 'bar', 'X' => 'YZ' } );
$b->meta('foo',''); # unset
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'X' => 'YZ' } );

eval { $b->meta( 'format' => 'foo' ); }; ok( $@, 'detect invalid FORMAT' );
$b->meta( 'format' => 'FOO-BEACON' );
is( $b->meta('format'), 'FOO-BEACON' );

is( $b->meta('COUNT'), undef, 'meta("COUNT")' );
is( $b->count, 0, 'count()' );
$b->meta('count' => 7);
is( $b->count, 7, 'count()' );
is( $b->line, 0, 'line()' );

# line parsing
my %t = (
  "qid" => ["qid","","",""],
  "qid|\t" => ["qid","","",""],
  "qid|" => ["qid","","",""],
  "qid|lab" => ["qid","lab","",""],
  "qid|lab|dsc" => ["qid","lab","dsc",""],
  "qid| |dsc" => ["qid","","dsc",""],
  "qid||dsc" => ["qid","","dsc",""],
  "qid|u:ri" => ["qid","","","u:ri"],
  "qid|lab|dsc|u:ri" => ["qid","lab","dsc","u:ri"],
  "qid|lab|u:ri" => ["qid","lab","","u:ri"],
  " \t" => [],
  "" => [],
  "qid|lab|dsc|u:ri|foo" => "found too many parts (>4), divided by '|' characters",
  "|qid|u:ri" => [],
  "qid|lab|dsc|abc" => "URI part has not valid URI form",
);
while (my ($line, $link) = each(%t)) {
    $r = $b->parselink( $line );
    is_deeply( $r, $link );
}

# file parsing
$b = new Data::Beacon( "t/beacon1.txt" );
is_deeply( { $b->meta() }, {
  'FORMAT' => 'BEACON',
  'TARGET' => 'http://example.com/{ID}',
  'FOO' => 'bar',
  'PREFIX' => 'x:'
}, "parsing meta fields" );

is( $b->line, 6, 'line()' );
$b->parse();

eval { $b = new Data::Beacon( error => 'xxx' ); }; ok( $@, 'error handler' );

# my $e;
# $b = new Data::Beacon( "t/beacon1.txt", e );

# TODO: test handlers (which should not be reset by parse unless wanted)

__END__

# Serializing is currently implemented in SeeAlso::Response only

use SeeAlso::Response;

# serializing BEACON

my $r = SeeAlso::Response->new( "|x|" );
$r->add( "a||", "|b", "http://example.com|" );
is( $r->toBEACON(), "x|a|b|http://example.com" );

$r->add( "y", "z|", "foo:bar" );
is( $r->toBEACON(), "x|a|b|http://example.com\nx|y|z|foo:bar" );

$r = SeeAlso::Response->new( "x" );
$r->add( "a||", "", "http://example.com|" );
$r->add( "", "d", "foo:bar" );
$r->add( "", "", "http://example.com" );
is( $r->toBEACON(), join("\n",
  "x|a|http://example.com",
  "x||d|foo:bar",
  "x|http://example.com"
) );

$r = SeeAlso::Response->new( "x" );
$r->add( "", "", "" );
$r->add( "a", "b" ); # no URI
#$r->add( "", "", "http://example.com" );
is( $r->toBEACON(), join("\n", 
  "x|a|b",
 # "x||d|foo:bar",
 # "x|http://example.com"
) );
