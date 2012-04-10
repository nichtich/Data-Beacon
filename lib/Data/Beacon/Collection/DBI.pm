use strict;
use warnings;
package Data::Beacon::Collection::DBI;
#ABSTRACT: Collection of BEACONs in a database

use base 'Data::Beacon::Collection';
use Data::Beacon::DBI;
use Carp qw(croak);
use Scalar::Util qw(reftype);
use DBI;

=head1 DESCRIPTION

This class is a subclass of L<Data::Beacon::Collection>.

=head1 METHODS

=head2 new ( ... )

Create a new Beacon collection in a database.

=cut

sub new {
    my $class = shift;
    my $self = bless { }, $class;

    $self->_init( @_ );
    croak $self->lasterror if $self->errors;

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

Insert a named Beacon (L<Data::Beacon>). This method works as 'upsert',
that means you can replace or add a Beacon. Returns the inserted Beacon
as L<Data::Beacon::DBI> or undef on error.

=cut

sub insert {
    my ($self, $name, $beacon) = @_;
    return unless $self->connected;

    my %meta = $beacon->meta();
    my $format = $meta{BEACON};
    delete $meta{BEACON};

    $self->{dbh}->{RaiseError} = 1;
    eval {
        $self->{dbh}->begin_work; # begin transaction

        my $rows = $self->{dbh}->do('DELETE FROM beacons WHERE bname = ?', {}, $name);
        $self->{dbh}->do('DELETE FROM links WHERE bname = ?', {}, $name) if $rows > 0;
 
        my $sql='INSERT INTO beacons (bname,bmeta,bvalue) VALUES (?,?,?)';
        my $sth = $self->{dbh}->prepare($sql);

        foreach my $key ( keys %meta ) {
            my $rv = $sth->execute( $name, $key, $meta{$key} );
        }

        $sql = 'INSERT INTO links ( bname, source, label, description, target )'
             . ' VALUES ( ?, ?, ?, ?, ? )';
        $sth = $self->{dbh}->prepare( $sql );
        if (!$sth) {
            $self->_handle_error( $self->{dbh}->errstr );
            return;
        }

        $sth->execute_for_fetch( sub { 
            my @link = $beacon->nextlink;
            return unless @link;
            my $link = [ $name, $link[0], $link[1], $link[2], $link[3] ];
            return $link;
        } );
        $sth->finish;

        $self->{dbh}->commit;
    };
    if ($@) {
        $self->{dbh}->{RaiseError} = 0;
        $self->_handle_error( $@ );
        return; 
    }
    $self->{dbh}->{RaiseError} = 0;

    return $self->get( $name );
}

=head2 remove ( $name )

Remove a named Beacon. Returns true if an existing Beacon has been removed.

=cut

sub remove {
    my ($self, $name) = @_;
    return unless $self->connected;

    $self->{dbh}->begin_work; # begin transaction
    my $rows = $self->{dbh}->do('DELETE FROM beacons WHERE bname = ?', {}, $name);
    $rows = 1*$rows if defined $rows; # 1*"0E0" = 0
    if ($rows) {
        $self->{dbh}->do('DELETE FROM links WHERE bname = ?', {}, $name);
        $self->{dbh}->commit; # TODO what if the previous do failed?
        return $rows;
    } else {
        $self->{dbh}->rollback;
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
    my $sql = 'SELECT DISTINCT bname FROM beacons';
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

=head2 errors

Returns the number of errors or zero.

=cut

sub errors {
    return $_[0]->{errors};
}

=head2 _handle_error ( $msg )

Internal error handler that calls a custom error handler,
increases the error counter and stores the last error. 

=cut

sub _handle_error {
    my $self = shift;
    $self->{lasterror} = [ @_ ];
    $self->{errors}++;
    $self->{error_handler}->( @_ ) if $self->{error_handler};
}


sub _init {
    my $self = shift;
    my (%param) = @_;

    $self->{lasterror} = [];
    $self->{errors} = 0;
    $self->{error_handler} = undef;

    my $dsn = $param{dbi};
    $dsn = "dbi:$dsn" unless $dsn =~ /^dbi:/;

    if ($param{error}) {
        croak "error handler must be code"
            unless reftype( $param{error} ) eq 'CODE';
        $self->{'error_handler'} = $param{error};
    }
    return unless $dsn;

    $self->{dbh} = eval {
        DBI->connect( $dsn, $param{user}, $param{password},
            { RaiseError => 0, PrintError => 0, AutoCommit => 1 } 
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
            push @statements, <<'SQL';
CREATE TABLE IF NOT EXISTS beacons (
  bname, 
  bmeta, 
  bvalue,
  UNIQUE(bname,bmeta) ON CONFLICT REPLACE
)
SQL
            push @statements, <<'SQL';
CREATE TABLE IF NOT EXISTS links (
  bname, 
  source, 
  label, 
  description, 
  target
)
SQL
        } elsif ( $driver eq 'mysql' ) {
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS beacons (
  bname VARCHAR(32) NOT NULL, 
  bmeta VARCHAR(64) NOT NULL, 
  bvalue VARCHAR(128) NOT NULL,
  UNIQUE(bname,bmeta),
  INDEX(bname,bmeta)
) ENGINE=InnoDB
SQL
            push @statements, <<"SQL";
CREATE TABLE IF NOT EXISTS links (
  bname VARCHAR(32) NOT NULL,
  source VARCHAR(64) NOT NULL,
  label VARCHAR(128) NOT NULL,
  description VARCHAR(128) NOT NULL, 
  target VARCHAR(128) NOT NULL,
  INDEX (bname),
  INDEX (bname,source)
) ENGINE=InnoDB
SQL
        } elsif ( $driver eq 'pg' ) {
            # Postgres does not know CREATE TABLE IF NOT EXISTS :-(
            push @statements, <<'SQL';
CREATE OR REPLACE FUNCTION create_beacon_db() returns void AS
$$
BEGIN
    IF NOT EXISTS(SELECT * FROM information_schema.tables WHERE
        table_catalog = CURRENT_CATALOG AND table_schema = CURRENT_SCHEMA
        AND table_name = 'beacons') THEN

CREATE TABLE beacons (
  bname VARCHAR(32) NOT NULL, 
  bmeta VARCHAR(64) NOT NULL, 
  bvalue VARCHAR(128) NOT NULL
);

        CREATE UNIQUE INDEX ON beacons (bname,bmeta);

CREATE TABLE links (
  bname VARCHAR(32) NOT NULL,
  source VARCHAR(64) NOT NULL,
  label VARCHAR(128) NOT NULL,
  description VARCHAR(128) NOT NULL, 
  target VARCHAR(128) NOT NULL
);
        CREATE INDEX ON links (bname);
        CREATE INDEX ON links (bname,source);
    END IF;
END;
$$
language 'plpgsql';

SELECT create_beacon_db();
SQL
       } else {
            die ("Unknown DBI driver: '$driver'");
        }

        $self->{dbh}->begin_work; # begin transaction
        foreach my $sql (@statements) {
            if (!$self->{dbh}->do($sql)) {
                $self->{dbh}->rollback;
                die ("Failed to init database");
            }
        }
        $self->{dbh}->commit;
    };
    if ($@) {
        $self->_handle_error( $@ );
    }

    $self->{dbh}->{RaiseError} = 0;
}

1;
