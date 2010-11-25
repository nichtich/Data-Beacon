package Data::Beacon::Collection;

use strict;
use warnings;

=head1 NAME

Data::Beacon::Collection - Abstract collection of named BEACON link sets.

=cut

use Data::Beacon;
use Data::Beacon::Collection::DBI;
use Carp;

our $VERSION = '0.0.1';

=head1 DESCRIPTION

Actually this class represents a hash that stores Beacon objects.

The current implementation is only a dummy. 

See L<Data::Beacon::Collection::DBI> 
and L<Data::Beacon::Collection::Files>
for implementation drafts.

=head1 METHODS

=head2 new ( { param => value ... } )

Create a new Beacon collection. Up to know only collections in a
database (L<Data::Beacon::Collection::DBI>) are supported, so you 
must specify at least parameter C<dbi> or this method will croak.

=cut

sub new {
    my ($class, %param) = @_;

    return Data::Beacon::Collection::DBI->new( %param )
        if $param{dbi};
 
    croak('Data::Beacon::Collection->new requires parameter dbi');
}

=head2 get ( $name )

Get a named Beacon.

=cut

sub get {
    my ($self, $name) = @_;
    # ...
}

=head2 insert ( $name, $beacon )

Insert a named Beacon. This method works as 'upsert',
that means you can replace or add a Beacon.

=cut

sub insert {
    my ($self, $name, $beacon) = @_;
    # ...
}

=head2 remove ( $name )

Remove a named Beacon.

=cut

sub remove {
    my ($self, $name) = @_;
    # ...
}

=head2 list ( [ %meta ] )

List the names of all namad Beacons. Optionally you can ask
for specific meta fields that must match.

=cut

sub list {
    my ($self, %meta) = @_;
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

