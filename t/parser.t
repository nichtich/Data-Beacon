use strict;
use Test::More;
use Data::Beacon::Parser;

sub parse_link(@) {
    my $p = Data::Beacon::Parser->new( from => \$_[0] );
    my @link = $p->next;
    is_deeply \@link, $_[1];
    is_deeply [$p->expand(@link)], $_[2] if $_[2];
}

parse_link 'foo', => ['foo','foo'];
parse_link 'http://example.org/', => ['http://example.org/','http://example.org/'];

parse_link 'http://example.org/foo|Hello World!|http://example.com/foo' 
    => ['http://example.org/foo','http://example.com/foo','Hello World!'];

parse_link 'http://example.com/people/alice||urn:isbn:0123456789'
    => ['http://example.com/people/alice','urn:isbn:0123456789',''];


parse_link 'http://example.com/people/alice|http://example.com/documents/23.about',
    => ['http://example.com/people/alice','http://example.com/documents/23.about'];
    
done_testing;
