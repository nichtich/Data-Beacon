package Data::Beacon::DBI;

use strict;
use warnings;

=head1 NAME

Data::Beacon::DBI - Stores a BEACON in a database

=cut

use base 'Data::Beacon';
use Carp qw(croak);
use DBI;

our $VERSION = '0.0.1';

=head1 DESCRIPTION

This class is a subclass of L<Data::Beacon>. Each instance is connected
to a specific Beacon collection as L<Data::Beacon::Collection::DBI>.

The current version is just a draft.

=head1 METHODS

=head2 new ( $collection, $name )

...may return undef...

=cut

sub new {
    my $class = shift;
    my $self = bless { }, $class;

    $self->_init( @_ );

    # check whether this beacon exists
    return unless $self->meta('FORMAT');

    return $self;
}

=head2 meta ( [ $key [ => $value [ ... ] ] ] )

Get and/or set one or more meta fields. Returns a hash (no arguments),
or string or undef (one argument), or croaks on invalid arguments.

=cut

sub meta {
    my $self = shift;

    # get all meta fields
    my $meta = $self->{collection}->{dbh}->selectall_hashref(
        'SELECT beacon_meta,beacon_value FROM beacons WHERE beacon_name = ?',
        'beacon_meta', {}, $self->{name}
    );
    return unless $meta and keys %$meta;

    %{$meta} = map { $_ => $meta->{$_}->{beacon_value} } keys %$meta;
    
    # always include COUNT
    $meta->{COUNT} = $self->count;

    # TODO: get specific meta field or set meta field(s)
    # never change the name!
    # changing PREFIX or TARGET may harm integrity of the Beacon!

    $self->{meta} = $meta;
    return %{$meta};
}

=head2 metafields 

Return all meta fields, serialized and sorted as string. This
method is derived L<from Data::Beacon|Data::Beacon/metafields>.

=cut

=head2 count

Returns the number of links in this Beacon, or zero.

=cut

sub count {
    my $self = shift;

    my $count = $self->{collection}->{dbh}->selectall_arrayref(
        'SELECT COUNT(*) FROM links WHERE beacon_name = ?',
        {}, $self->{name}
    );
    return 0 unless $count;
    return $count->[0]->[0];
}

=head2 line

Always returns zero.

=cut

sub line {
    return 0;
}

=head2 lasterror

Returns the last error message (if any). This method 
is derived L<from Data::Beacon|Data::Beacon/lasterror>.

=cut

=head2 errorcount

Returns the current number of errors or zero.

=cut

sub errorcount {
    my $self = shift;

    # ...
}

=head2 parse ( { handler => coderef } )

Iterate over all links. You can pass a C<link> handler, and/or an
C<error> handler.

=cut

sub parse {
    my ($self, %param) = @_;

    # TODO: support 'pre'
    foreach my $name (qw(error link)) {
        next unless defined $param{$name};
        croak "$name handler must be code"
            unless ref($param{$name}) and ref($param{$name}) eq 'CODE';
        $self->{$name.'_handler'} = $param{$name};
    }

    $self->{iterator}->finish if $self->{iterator};

    $self->{meta} = { $self->meta }; # TODO: we only need PREFIX, TARGET, MSG etc.

    my $sql = 'SELECT link_id, link_label, link_descr, link_to FROM links WHERE beacon_name = ?';

    eval {
        $self->{iterator} = $self->{collection}->{dbh}->prepare($sql, { RaiseError => 1 });
        $self->{iterator}->execute( $self->{name} );
    };
    if ($@) {
        $self->{iterator} = undef;
        $self->_handle_error( $@ );
    } else { # TODO: 
        while (my $link = $self->nextlink()) {
            if ($self->{link_handler}) {
                eval { $self->{link_handler}->( @$link ); };
                $self->_handle_error( "link handler died: $@" ) if $@;
            }
        }
    }
}

=head2 nextlink

Return the next link when iterating (as array reference), or undef.

=cut

sub nextlink {
    my $self = shift;

    return unless $self->{iterator};

    my $link = $self->{iterator}->fetchrow_arrayref;
    if (!$link) {
        # TODO: could also be an error
        $self->{iterator} = undef;
        return;
    }

    return [ $self->_expanded_link( $link ) ];
}

=head2 lastlink

Returns the last link when iterating.
Implemented L<in Data::Beacon|Data::Beacon/lastlink>.

=cut

=head2 query ( $id )

TODO

=cut

sub query {
    my ($self, $id) = @_;

    my $sql = <<"SQL";
SELECT link_label, link_descr, link_to FROM links 
WHERE beacon_name = ? AND link_id = ?
SQL
    my $dbh = $self->{collection}->{dbh};

    my $result = $dbh->selectall_arrayref($sql,{},$self->{name}, $id);

    if ( !$result ) {
        $self->_handle_error( $dbh->errstr );
        return;
    }

    my $links = [ map { 
        [ $id, $self->_expanded_link( $_ ) ]
    } @$result ];

    return $links;
}

=head1 INTERNAL METHODS

=head2 _init

=cut

sub _init {
    my $self = shift;
    my $collection = shift;
    my $name = shift;

    croak ('expected Data::Beacon::Collection::DBI')
        unless UNIVERSAL::isa( $collection, 'Data::Beacon::Collection::DBI' );
    # TODO: croak on more errors

    $self->{errorcount} = 0;
    $self->{lasterror} = [];
    $self->{name} = $name;
    $self->{collection} = $collection;

}


=head2 _expanded_link

Expand an link with PREFIX and TARGET, if given. Does not call C<meta>
but uses the cached meta values. 
Returns an array instead of an array reference!

TODO: Should be moved to L<Data::Beacon>.

=cut

sub _expanded_link {
    my $self = shift;
    my $link = shift;

    my $fullid = $link->[0];
    my $prefix = $self->{meta}->{PREFIX};
    $fullid = $prefix . $fullid if defined $prefix;

    my $fulluri;
    my $target = $self->{meta}->{TARGET};
    if (defined $target) {
        $fulluri = $target;
        my ($id,$label) = ($link->[0], $link->[1]);
        $fulluri =~ s/{ID}/$id/g;
        $fulluri =~ s/{LABEL}/$label/g;
    } else {
        $fulluri = $link->[3]; 
    }

    # $link may be readonly
    #push @$link, $fullid;
    #push @$link, $fulluri;

    return ( @$link, $fullid, $fulluri );
}

1;

__END__

=head1 FUTURE METHODS

The following methods are not implemented yet.

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

=head1 AUTHOR

Jakob Voss C<< <jakob.voss@gbv.de> >>

=head1 LICENSE

Copyright (C) 2010 by Verbundzentrale Goettingen (VZG) and Jakob Voss

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.

In addition you may fork this library under the terms of the 
GNU Affero General Public License.

