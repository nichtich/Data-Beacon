use strict;
use warnings;
package Data::Beacon::Collection;
#ABSTRACT: Abstract collection of named BEACON link sets

use Data::Beacon;
use Data::Beacon::Collection::DBI;
use Carp;

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
