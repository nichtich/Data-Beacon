package Data::Beacon::DBI;

use strict;
use warnings;

=head1 NAME

Data::Beacon::DBI - Stores a BEACON in a database

=cut

use base 'Data::Beacon';
use Carp;

our $VERSION = '0.0.1';

=head1 DESCRIPTION

This class is a subclass of L<Data::Beacon>.

=head1 METHODS

=head2 new ( ... )

...

=cut

sub new {
    my $class = shift;
    my $self = bless { }, $class;

    # ...

    return $self;
}

=head2 meta ( [ $key [ => $value [ ... ] ] ] )

Get and/or set one or more meta fields. Returns a hash (no arguments),
or string or undef (one argument), or croaks on invalid arguments.

=cut

sub meta {
    my $self = shift;

    # ...
}

=head2 count

=cut

sub count {
    my $self = shift;

    # ...
}

=head2 line

Always returns zero.

=cut

sub line {
    return 0;
}

=head2 lasterror

Returns the last error message (if any).

=cut

sub lasterror {
    my $self = shift;

    # ...
}

=head2 errorcount

Returns the current number of errors or zero.

=cut

sub errorcount {
    my $self = shift;

    # ...
}

=head2 metafields 

Return all meta fields, serialized and sorted as string.
Implemented L<in Data::Beacon|Data::Beacon/metafields>.

=cut

=head2 parse ( { handler => coderef | option => $value } )

Start iterating over all links. You can also call this method to rewind
iterating. In contrast to the L<Data::Beacon/parse>, this method does
not support a from parameter.

=cut

sub parse {
    my $self = shift;

    # ...
}

=head2 nextlink

Return the next link when iterating.

=cut

sub nextlink {
    my $self = shift;

    # ...
}

=head2 lastlink

Returns the last link when iterating.
Implemented L<in Data::Beacon|Data::Beacon/lastlink>.

=cut

=head2 query ( $id )

TODO

=cut

sub query {
    my $self = shift;

    # ...
}

=head2 append ( $links )

Add links.

=cut

sub append {
    my $self = shift;

    # ...
}

=head2 replace ( $id [ $links ] )

Insert, replace or remove links.

=cut

sub replace {
    my $self = shift;

    # ...
}

1;

__END__

=head1 AUTHOR

Jakob Voss C<< <jakob.voss@gbv.de> >>

=head1 LICENSE

Copyright (C) 2010 by Verbundzentrale Goettingen (VZG) and Jakob Voss

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.

In addition you may fork this library under the terms of the 
GNU Affero General Public License.

