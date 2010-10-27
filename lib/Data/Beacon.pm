package Data::Beacon;

use strict;
use warnings;

=head1 NAME

Data::Beacon - BEACON format parser and serializer

=cut

use Data::Validate::URI qw(is_uri);
use Time::Piece;
use Carp;

our $VERSION = '0.10';

=head1 SYNOPSIS

  use Data::Beacon;

  $beacon = new SeeAlso::Beacon( $beaconfile );

  $beacon->meta();                                   # get all meta fields
  $beacon->meta( 'DESCRIPTION' => 'my best links' ); # set meta fields
  $d = $beacon->meta( 'DESCRIPTION' );               # get meta field
  $beacon->meta( 'DESCRIPTION' => '' );              # unset meta field
  print $beacon->metafields();

  $beacon->parse();
  $beacon->parse( error => sub { print STDERR $_[0] . "\n" } );
  $beacon->parse( $beaconfile );


  $beacon->count(); # number of parsed links
  $beacon->lines(); # number of lines

#  $beacon->parse( [$file], \&handler ); # parse all lines
#  $beacon->query( $id );

=head1 DESCRIPTION

=cut

=head1 METHODS

=head2 new ( [ $from ] { parameter => value } )

Create a new Beacon object, optionally from a given file. If you specify a 
source via C<$from> argument or as parameter C<from =E<gt> $from>, it will
be opened for parsing and all meta fields will immediately be read from it.
Otherwise you get an empty, but initialized Beacon object. See the C<parse>
methods for more details.

=cut

sub new {
    my $class = shift;
    my $self = bless { }, $class;
    $self->_initparams( @_ );
    $self->_startparsing;
    return $self;
}

=head2 meta ( [ $key [ => $value [ ... ] ] ] )

Get and/or set one or more meta fields. Returns a hash (no arguments),
or string or undef (one argument), or croaks on invalid arguments. A
meta field can be unset by setting its value to the empty string.
The FORMAT field cannot be unset. This method may also croak if supplied
invalid field for known fields such as FORMAT, PREFIX, FEED, EXAMPLES,
REVISIT, TIMESTAMP.

=cut

sub meta {
    my $self = shift;
    return %{$self->{meta}} unless @_;

    if (@_ == 1) {
        my $key = uc(shift @_);
        $key =~ s/^\s+|\s+$//g;
        return $self->{meta}->{$key};
    }

    croak('Wrong number of arguments in SeeAlso::Beacon->meta') if @_ % 2;

    my %list = (@_);
    foreach my $key (keys %list) {
        croak('invalid meta name: "'.$key.'"') 
            unless $key =~ /^\s*([a-zA-Z_-]+)\s*$/; 
        my $value = $list{$key};
        $key = uc($1);
        $value =~ s/\s+|\s+$|\n//g;
        if ($value eq '') { # empty field: unset
            croak 'You cannot unset meta field #FORMAT' if $key eq 'FORMAT';
            delete $self->{meta}->{$key};
        } else { # check format of known meta fields
            if ($key eq 'TARGET') {

                # TODO...{ID} $PND etc.

            } elsif ($key eq 'FEED') {
                croak 'FEED meta value must be a HTTP/HTTPS URL' 
                    unless $value =~ 
/^http(s)?:\/\/[a-z0-9-]+(.[a-z0-9-]+)*(:[0-9]+)?(\/[^#|]*)?(\?[^#|]*)?$/i;
            } elsif ($key eq 'PREFIX') {
                croak 'PREFIX meta value must be a URI' 
                    unless is_uri($value);
            } elsif ( $key =~ /^(REVISIT|TIMESTAMP)$/) {
                if ($value =~ /^[0-9]+$/) { # seconds since epoch
                    $value = gmtime($value)->datetime(); 
                    # TODO: add warning about this conversion
                } else {
                    croak $key . ' meta value must be of form YYYY-MM-DDTHH:MM:SS'
                        unless $value = Time::Piece->strptime( $value, '%Y-%m-%dT%T' );
                    $value = $value->datetime();
                }
            } elsif ( $key eq 'FORMAT' ) {
                croak 'Invalid FORMAT, must be BEACON or end with -BEACON'
                    unless $value =~ /^([A-Z]+-)?BEACON$/;
            } elsif ( $key eq 'EXAMPLES' ) {
                my @examples = map { s/^\s+|\s+$//g; $_ } split '\|', $value;
                $self->{examples} = [ grep { $_ ne '' } @examples ];
                $value = join '|', @{$self->{examples}};
                if ($value eq '') { # yet another edge case: "EXAMPLES: |" etc.
                    delete $self->{meta}->{EXAMPLES};
                    next;
                }
                # NOTE: examples are not checked for validity, we may need PREFIX first
            }
            $self->{meta}->{$key} = $value;
        }
    }
}

=head2 count

Returns the number of links, successfully read so far, or zero. 
In contrast to C<meta('count')>, this method always returns a number.

=cut

sub count {
    my $count = $_[0]->meta('COUNT');
    return defined $count ? $count : 0;
}

=head2 line

Returns the current line number.

=cut

sub line {
    return $_[0]->{line};
}

=head2 metafields 

Return all meta fields, serialized and sorted as string.

=cut

sub metafields {
    my $self = shift;
    my %meta = $self->meta();
    my @lines = '#FORMAT: ' . $meta{'FORMAT'};
    delete $meta{'FORMAT'};
    my $count = $meta{'COUNT'};
    delete $meta{'COUNT'};
    # TODO: specific default order of fields
    foreach my $key (keys %meta) {
        push @lines, "#$key: " . $meta{$key}; 
    }
    push (@lines, "#COUNT: " . $count) if defined $count;

    return @lines ? join ("\n", @lines) . "\n" : "";
}

=head2 parse ( [ $from ] { parameter => value } )

Parse all remaining links. If provided a C<$from> parameter, this starts 
a new Beacon. That means the following is equivalent:

  $b = new SeeAlso::Beacon( $filename );

  $b = new SeeAlso::Beacon;
  $b->parse( $filename );

By default, errors are silently ignored, unless you specifiy an error 
handler.

=cut

sub parse {
    my $self = shift;

    $self->_initparams( @_ );
    $self->_startparsing if defined $self->{from}; # start from new source

    return unless $self->{fh};

    $self->{meta}->{COUNT} = 0;
    my $line = $self->{lookaheadline};
    goto(OH_MY_GOD_THE_EVIL_GOTO_WE_WILL_ALL_DIE) if defined $line;

    while ($line = readline $self->{fh}) {
        OH_MY_GOD_THE_EVIL_GOTO_WE_WILL_ALL_DIE:

        $self->{line}++;

        my $link = $self->parselink( $line );

        if (!ref($link)) { # error
            #$self->{errorcount}++;
            if ($self->{error_handler}) {
                $self->{error_handler}->( $link, $self->{line}, $line );
            } else {
                # TODO: add default error handler
            }
        } elsif (@$link) { # no empty line or comment

            # TODO: check whether id together with prefix is an URI
            # TODO: handle link

            $self->{meta}->{COUNT}++; # TODO: only if not error
        }
    } 

    # TODO: call end handler
}

=head2 parselink ( $line )

Parses a line, interpreted as link in BEACON format. Returns an array reference
with four values on success, an empty array reference for empty linkes, or an 
error string on failure. This method does not check whether the query identifier
is a valid URI, because it may be expanded by a prefix.

=cut

sub parselink {
    my ($self, $line) = @_;

    my @parts = map { s/^\s+|\s$//g; $_ } split('\|',$line);
    my $n = @parts;
    return [] if ($n < 1 || $parts[0] eq '');
    return "found too many parts (>4), divided by '|' characters" if $n > 4;
    my $link = [shift @parts,"","",""];

    $link->[3] = pop @parts
        if ($n > 1 && is_uri($parts[$n-2]));

    $link->[1] = shift @parts if @parts;
    $link->[2] = shift @parts if @parts;

    return "URI part has not valid URI form" if @parts; 

    return $link;
}

=head1 INTERNAL METHODS

If you directly call any of this methods, puppies will die.

=head2 _initparams ( [ $from ] { parameter => value } )

Initialize parameters as passed to C<new> or C<parse>.

=cut

sub _initparams {
    my $self = shift;

    $self->{from} = (@_ % 2) ? shift(@_) : undef;

    my %param = @_;
    $self->{from} = $param{from}
        if defined $param{from};

    if (defined $param{error}) { # TODO: do we want to unset an error handler?
        croak 'Error handler must be code'
            unless ref($param{error}) and ref($param{error}) eq 'CODE';
        $self->{error_handler} = $param{error};
    }

    # TODO: enable more handlers
}

=head2 _startparsing

Open a BEACON file and parse all meta fields. Calling this method will reset
the whole object but not the parameters as set with C<_initparams>. If no
source had been specified (with parameter C<from>), this is all the method 
does. If a source is given, it is opened and parsed. Parsing stops when the
first non-empty and non-meta field line is encountered. This line is internally
stored as lookahead.

=cut

sub _startparsing {
    my $self = shift;

    $self->{meta} = { 'FORMAT' => 'BEACON' };
    $self->{line} = 0;
    #$self->{errorcount} = 0;
    $self->{lookaheadline} = undef;

    $self->{examples} = [];

    return unless defined $self->{from};

    open $self->{fh}, $self->{from};
    # TODO: check error on opening stream

    # TODO: remove BOM (allowed in UTF-8)
    # /^\xEF\xBB\xBF/
    while (my $line = readline $self->{fh}) {
        $line =~ s/^\s+|\s*\n?$//g;
        if ($line eq '') {
            $self->{line}++;
            next;
        } elsif ($line =~ /^#([^:=\s]+)(\s*[:=]?\s*|\s+)(.*)$/) {
            $self->{line}++;
            $self->meta($1,$3); # TODO: check for errors and handle them?
        } else {
            $self->{lookaheadline} = $line;
            last;
        }
    }
}

1;

__END__

=head1 AUTHOR

Jakob Voss C<< <jakob.voss@gbv.de> >>

=head1 LICENSE

Copyright (C) 2007-2010 by Verbundzentrale Goettingen (VZG) and Jakob Voss

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.
