package Data::Beacon::Collection::DBI;

use strict;
use warnings;

=head1 NAME

Data::Beacon::Collection::DBI - Collection of BEACONs in a database

=cut

use base 'Data::Beacon::Collection';
use Carp qw(croak);
use DBI;

our $VERSION = '0.0.1';

=head1 DESCRIPTION

This class is a subclass of L<Data::Beacon::Collection>.

=head1 METHODS

=head2 new ( ... )

...

=cut

sub new {
    my $class = shift;
    my $self = bless { }, $class;

    $self->_init( @_ );

    return $self;
}

=head2 connected

Return whether a database connection has been established.

=cut

sub connected {
    my $self = shift;
    return $self->{dbh};
}

=head1 INTERNAL METHODS

=cut

=head2 lasterror

Returns the last parsing error message (if any).

=cut

sub lasterror {
    return $_[0]->{lasterror}->[0];
}

=head2 _handle_error ( $msg )

Internal error handler that calls a custom error handler,
increases the error counter and stores the last error. 

=cut

sub _handle_error {
    my $self = shift;
    $self->{lasterror} = [ @_ ];
    $self->{errorcount}++;
    $self->{error_handler}->( @_ ) if $self->{error_handler};
}


sub _init {
    my $self = shift;
    my ($dsn) = @_;
    
    $self->{lasterror} = [];
    $self->{errorcount} = 0;

    my ($user, $password) = ("","");
    return unless $dsn;

    $self->{dbh} = DBI->connect($dsn, $user, $password, {PrintError => 0});
    if ( !$self->{dbh} ) {
        $self->_handle_error( $DBI::errstr );
        return;
    }

    # TODO: do not create tables by default and use transaction

    my $create = <<SQLITE;
CREATE TABLE IF NOT EXISTS beacons (
  id, name, meta, value, UNIQUE(id), UNIQUE(name), 
  UNIQUE(name,meta) ON CONFLICT REPLACE
)
SQLITE

    $self->{dbh}->do($create)
      or $self->_handle_error( $self->{dbh}->errstr, "", "" );

    $create = <<SQLITE;
CREATE TABLE IF NOT EXISTS links (
  beacon_id, link_id, label, description, link_to
)
SQLITE

    $self->{dbh}->do($create)
      or $self->_handle_error( $self->{dbh}->errstr, "", "" );

    # $dbh->commit

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

