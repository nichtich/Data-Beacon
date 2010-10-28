#!perl -Tw

use strict;
use warnings;

use Test::More qw(no_plan);

use_ok('Data::Beacon');

my $r;
my $b = new Data::Beacon();
isa_ok($b,'Data::Beacon');

is( $b->errorcount, 0 );

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

is( $b->errorcount, 0, 'croaking errors are not counted' );

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
  "qid|  lab |dsc" => ["qid","lab","dsc",""],
  "qid| | dsc" => ["qid","","dsc",""],
  " qid||dsc" => ["qid","","dsc",""],
  "qid |u:ri" => ["qid","","","u:ri"],
  "qid |lab  |dsc|u:ri" => ["qid","lab","dsc","u:ri"],
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
is( $b->lasterror, "found too many parts (>4), divided by '|' characters" );

is( $b->errorcount, 1 );

eval { $b = new Data::Beacon( error => 'xxx' ); }; ok( $@, 'error handler' );
is( $b->errorcount, 1 );

$b->parse("xxx"); #; ok( $@, 'error parsing' );
is( $b->errorcount, 1 );

my $e = $b->lasterror;
is( $e, 'Failed to open xxx', 'lasterror, scalar context' );

my @es = $b->lasterror;
is_deeply( \@es, [ 'Failed to open xxx', 0, '' ], 'lasterror, list context' );

$b->parse( { } );
is( $b->errorcount, 1, 'cannot parse a hashref' );

$b->parse( \"x:from|x:to\n\n|comment" );
is( $b->count, 1, 'parse from string' );
is( $b->line, 3, '' );


my @tmplines = ( '#FOO: bar', '#DOZ', '#BAZ: doz' );
$b->parse( from => sub { return shift @tmplines; } );
is( $b->line, 3, 'parse from code ref' );
is( $b->count, 0, '' );
is( $b->metafields, "#FORMAT: BEACON\n#BAZ: doz\n#FOO: bar\n#COUNT: 0\n" );

$b->parse( from => sub { die 'hard'; } );
is( $b->errorcount, 1 );
ok( $b->lasterror =~ /^hard/, 'dead input will not kill us' );

#my @tmplines = ( '#PREFIX: http://example.com/?q={ID}', 'a|foo:bar', )

use Data::Validate::URI qw(is_uri);

my @p = ( 
    ["","","",""], "",
    ["a","b","c","z"], "a|b|c|z",
    ["a","b","c",""], "a|b|c",
    ["a","b","","z"], "a|b||z",
    ["a","b","",""], "a|b",
    ["a","","",""], "a",
    ["a","","","z"], "a|||z",
    ["x","a||","","http://example.com|"], "x|a|http://example.com",
    ["x","","|d","foo:bar"], "x||d|foo:bar",
    ["x","|","","http://example.com"], "x|http://example.com",
    ["","","","http://example.com"], ""
);
while (@p) {
    my $in = shift @p;
    my $out = shift @p;
    my $line = Data::Beacon::beaconlink( @{$in} );
    is( $line, $out, 'beaconlink' );

    # TODO $in->[0] may be no URI at all, so it should not be valid then!
    if ($out ne '' and is_uri($in->[3])) {
        my $link2;
        #print "$line\n";
        $b->parse( \$line, 'link' => sub { $link2 = [ @_ ]; } );
        is_deeply( $link2, $in );
    } 
}
