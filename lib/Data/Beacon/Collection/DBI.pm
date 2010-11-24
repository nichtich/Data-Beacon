package Data::Beacon::Collection::DBI;

use strict;
use warnings;

=head1 NAME

Data::Beacon::Collection::DBI - Collection of BEACONs in a database

=cut

use base 'Data::Beacon::Collection';
use Data::Beacon::DBI;
use Carp qw(croak);
use Scalar::Util qw(reftype);
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

=head2 get ( $name )

Get a named Beacon as L<Data::Beacon::DBI> object or undef.

=cut

sub get {
    my ($self, $name) = @_;
    return unless $self->connected;

    my $beacon = Data::Beacon::DBI->new( $self, $name );

    return $beacon;
}

=head2 insert ( $name, $beacon )

Insert a named Beacon. This method works as 'upsert',
that means you can replace or add a Beacon.

Returns the inserted Beacon as L<Data::Beacon::DBI>.

=cut

sub insert {
    my ($self, $name, $beacon) = @_;
    return unless $self->connected;

    my %meta = $beacon->meta();
    my $format = $meta{BEACON};
    delete $meta{BEACON};

    # my ($id) = $self->{dbh}->selectrow_array('SELECT MAX(beacon_id) FROM beacons');
    # $id ||= 1;

    $self->remove( $name ); # TODO: include this in the transaction

    # MySQL would need 'ON DUPLICATE KEY UPDATE' unless we remove the Beacon
    my $sql=<<"SQL";
INSERT INTO beacons ( beacon_name, beacon_meta, beacon_value )
VALUES ( ?, ?, ? );
SQL
    my $sth = $self->{dbh}->prepare($sql);

    foreach my $key ( keys %meta ) {
        my $rv = $sth->execute( $name, $key, $meta{$key} );
    }

    $sql = <<"SQL";
INSERT INTO links ( beacon_name, link_id, link_label, link_descr, link_to )
VALUES ( ?, ?, ?, ?, ? )
SQL
    $sth = $self->{dbh}->prepare( $sql );
    if (!$sth) {
        $self->_handle_error( $self->{dbh}->errstr );
        return;
    }

    $sth->execute_for_fetch( sub { 
        my $link = $beacon->nextlink();
        return unless $link;
        $link = [ $name, $link->[0], $link->[1], $link->[2], $link->[3] ];
        return $link;
    } );
    $sth->finish;

    $self->{dbh}->commit; # TODO: catch errors

    return $self->get( $name );
}

=head2 remove ( $name )

Remove a named Beacon. Returns true if an existing Beacon has been removed.

=cut

sub remove {
    my ($self, $name) = @_;
    return unless $self->connected;

    my $rows = $self->{dbh}->do('DELETE FROM beacons WHERE beacon_name = ?', {}, $name);
    $rows = 1*$rows if defined $rows; # 1*"0E0" = 0
    if ($rows) {
        $self->{dbh}->do('DELETE FROM links WHERE beacon_name = ?', {}, $name);
        $self->{dbh}->commit(); # TODO what if the previous do failed?
        return $rows;
    }

    $self->_handle_error( $DBI::errstr ) if $DBI::errstr;
    return 0;
}

=head2 list ( [ %meta ] )

List the names of all namad Beacons. Optionally you can ask
for specific meta fields that must match (not implemented yet).

=cut

sub list {
    my ($self, %meta) = @_;
    return () unless $self->connected;

    # TODO: query for specific beacons with meta fields
    my $sql = 'SELECT DISTINCT beacon_name FROM beacons';
    my $list = $self->{dbh}->selectall_arrayref($sql);

    if ( !$list ) {
        $self->_handle_error( $self->{dbh}->errstr );
        return;
    }

    return map { $_->[0] } @$list;
}

=head1 INTERNAL METHODS

=cut

=head2 lasterror

Returns the last parsing error message (if any).

=cut

sub lasterror {
    return $_[0]->{lasterror}->[0];
}

=head2 errorcount

Returns the number of errors or zero.

=cut

sub errorcount {
    return $_[0]->{errorcount};
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
    my $dsn = shift;;
    my (%param) = @_;
    
    $self->{lasterror} = [];
    $self->{errorcount} = 0;
    $self->{error_handler} = undef;

    if ($param{error}) {
        croak "error handler must be code"
            unless reftype( $param{error} ) eq 'CODE';
        $self->{'error_handler'} = $param{error};
    }
    return unless $dsn;

    $self->{dbh} = eval {
        DBI->connect( $dsn, $param{user}, $param{password},
            { RaiseError => 0, PrintError => 0, AutoCommit => 0 } 
        );
    };
    if ( !$self->{dbh} ) {
        my $msg = $DBI::errstr;
        $msg ||= "failed to connect to database";
        $self->_handle_error( $msg );
        return;
    }

# TODO: support other databases (MySQL, Postgres, Berkeley DB etc.)
    my $driver = lc($self->{dbh}->{Driver}->{Name});

    $self->{dbh}->{RaiseError} = 1;


    my @statements;

    # beacons: each line holds one meta field
    # links: each line holds one link

    eval {
        if ( $driver eq 'sqlite' ) {
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS beacons (
  beacon_name, 
  beacon_meta, 
  beacon_value,
  UNIQUE(beacon_name,beacon_meta) ON CONFLICT REPLACE
)
SQL
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS links (
  beacon_name, 
  link_id, 
  link_label, 
  link_descr, 
  link_to
)
SQL
        } elsif ( $driver eq 'mysql' ) {
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS beacons (
  beacon_name VARCHAR(32) NOT NULL, 
  beacon_meta VARCHAR(64) NOT NULL, 
  beacon_value VARCHAR(128) NOT NULL,
  UNIQUE(beacon_name,beacon_meta),
  INDEX(beacon_name,beacon_meta)
) ENGINE=InnoDB
SQL
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS links (
  beacon_name VARCHAR(32) NOT NULL,
  link_id VARCHAR(64) NOT NULL,
  link_label VARCHAR(128) NOT NULL,
  link_descr VARCHAR(128) NOT NULL, 
  link_to VARCHAR(128) NOT NULL,
  INDEX (beacon_name),
  INDEX (beacon_name,link_id)
) ENGINE=InnoDB
SQL
        } else {
            die ("Unknown DBI driver: '$driver'");
        }

        foreach my $sql (@statements) {
            $self->{dbh}->do($sql) or die( $self->{dbh}->errstr );
        }
        $self->{dbh}->commit;
    };
    if ($@) {
        $self->_handle_error( $@ );
    }

    $self->{dbh}->{RaiseError} = 0;
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

