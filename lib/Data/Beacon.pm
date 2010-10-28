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

use base 'Exporter';
our @EXPORT_OK = qw(beaconlink);

=head1 SYNOPSIS

  use Data::Beacon;

  $beacon = new SeeAlso::Beacon( $beaconfile );

  $beacon->meta();                                   # get all meta fields
  $beacon->meta( 'DESCRIPTION' => 'my best links' ); # set meta fields
  $d = $beacon->meta( 'DESCRIPTION' );               # get meta field
  $beacon->meta( 'DESCRIPTION' => '' );              # unset meta field
  print $beacon->metafields();

  $beacon->parse(); # proceed parsing links
  $beacon->parse( error => sub { print STDERR $_[0] . "\n" } );

  $beacon->parse( $beaconfile );
  $beacon->parse( \$beaconstring );
  $beacon->parse( sub { return $nextline } );

  $beacon->count();      # number of parsed links
  $beacon->lines();      # number of lines
  $beacon->errorcount(); # number of parsing errors

=head1 DESCRIPTION

This package implements a parser and serializer for BEACON format with
dedicated error handling.

  my $beacon = new SeeAlso::Beacon( ... );
  $beacon->parse( 'link' => \handle_link );

Alternatively you can use the parser as iterator (not implemented yet):

  my $beacon = new SeeAlso::Beacon( ... );
  while (my $link = $beacon->nextlink()) {
      handle_link( @{$link} );
  }

=head1 METHODS

=head2 new ( [ $from ] { handler => coderef } )

Create a new Beacon object, optionally from a given file. If you specify a 
source via C<$from> argument or as parameter C<from =E<gt> $from>, it will
be opened for parsing and all meta fields will immediately be read from it.
Otherwise you get an empty, but initialized Beacon object. See the C<parse>
methods for more details about possible handlers as parameters.

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
The FORMAT field cannot be unset. This method may also croak if a known
fields, such as FORMAT, PREFIX, FEED, EXAMPLES, REVISIT, TIMESTAMP is
tried to set to an invalid value. Such an error will not change the
error counter of this object or modify C<lasterror>.

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

                # TODO: check {ID} $PND etc.

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
                # NOTE: examples are not checked for validity, may need PREFIX
            }
            $self->{meta}->{$key} = $value;
        }
    }
}

=head2 count

Returns the number of links, successfully read so far, or zero. In contrast to
C<meta('count')>, this method always returns a number. Note that valid links
that could be parsed but not handled by a custom link handler, are included.

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

=head2 lasterror

Returns the last parsing error message (if any). Errors triggered by directly
calling C<meta> are not included. In list context returns a list of error
message, line number, and current line content.

=cut

sub lasterror {
    return wantarray ? @{$_[0]->{lasterror}} : $_[0]->{lasterror}->[0];  
}

=head2 errorcount

Returns the number of parsing errors or zero.

=cut

sub errorcount {
    return $_[0]->{errorcount};
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
    # TODO: specific default order of known fields
    foreach my $key (sort keys %meta) {
        push @lines, "#$key: " . $meta{$key}; 
    }
    push (@lines, "#COUNT: " . $count) if defined $count;

    return @lines ? join ("\n", @lines) . "\n" : "";
}

=head2 parse ( [ $from ] { handler => coderef } )

Parse all remaining links. If provided a C<from> parameter, this starts 
a new Beacon. That means the following three are equivalent:

  $b = new SeeAlso::Beacon( $from );

  $b = new SeeAlso::Beacon( from => $from );

  $b = new SeeAlso::Beacon;
  $b->parse( $from );

If C<from> is a scalar, it is used as file to parse from. Alternatively you
can supply a string reference, or a code reference.

By default, all errors are silently ignored, unless you specifiy an C<error>
handler. The last error can be retrieved with the C<lasterror> method and the
number of errors by C<errorcount>. Returns true only if C<errorcount> is zero 
after parsing. Note that some errors may be less important.

Finally, the C<link> handler can be a code reference to a method that is
called for each link (that is each line in the input that contains a valid
link). The following arguments are passed to the handler:

...

The number of sucessfully parsed links is returned by C<count>.

=cut

sub parse {
    my $self = shift;

    $self->_initparams( @_ );
    $self->_startparsing if defined $self->{from}; # start from new source

    $self->{meta}->{COUNT} = 0;
    my $line = $self->{lookaheadline};
    $line = $self->_readline() unless defined $line;

    while (defined $line) {
        $self->{line}++;

        my $link = $self->parselink( $line );

        if (!ref($link)) {
            $self->_handle_error( $link, $self->{line}, $line );
        } elsif (@$link) { # no empty line or comment

            # TODO: check whether id together with prefix is an URI
            $self->{meta}->{COUNT}++; # TODO: only if not error

            if ($self->{link_handler}) {
                # TODO: what if link handler croaks?
                # does the link handler get expanded or compressed links?
                $self->{link_handler}->( @$link );
            }
        }
        $line = $self->_readline();
    } 

    # TODO: we ma check addittional integrity, e.g. examples etc.

    return $self->errorcount == 0;
}

=head2 parselink ( $line )

Parses a line, interpreted as link in BEACON format. Returns an array reference
with four values on success, an empty array reference for empty linkes, or an 
error string on failure. This method does not check whether the query identifier
is a valid URI, because it may be expanded by a prefix.

=cut

sub parselink {
    my ($self, $line) = @_;

    my @parts = map { s/^\s+|\s+$//g; $_ } split('\|',$line);
    my $n = @parts;
    return [] if ($n < 1 || $parts[0] eq '');
    return "found too many parts (>4), divided by '|' characters" if $n > 4;
    my $link = [shift @parts,"","",""];

    $link->[3] = pop @parts
        if ($n > 1 && is_uri($parts[$n-2]));

    $link->[1] = shift @parts if @parts;
    $link->[2] = shift @parts if @parts;

    return 'URI part has not valid URI form' if @parts; 

    return $link;
}

=head1 FUNCTIONS

The following functions can be exported on request.

=head2 beaconlink ( $id, $label, $description, $uri )

Serialize a link and return it as condensed string.
'C<|>' characters in link elements are silently removed.

=cut

sub beaconlink {
    my @link = map { s/\|//g; $_ } @_;
    return '' unless @link == 4 and $link[0] ne '';

    if ( is_uri($link[3]) ) {
        my $uri = pop @link;
        if ($link[2] eq '') {
           pop @link;
           pop @link if ($link[1] eq '');
        }
        push @link, $uri;
    } else {
        if ($link[3] eq '') {
            pop @link;
            if ($link[2] eq '') {
                pop @link;
                pop @link if ($link[1] eq '');
            }
        }
    }
 
    return join('|', @link);
}

=head1 INTERNAL METHODS

If you directly call any of this methods, puppies will die.

=head2 _initparams ( [ $from ] { handler => coderef } )

Initialize parameters as passed to C<new> or C<parse>. Known parameters
are C<from>, C<error>, and C<link>. C<from> is not checked here.

=cut

sub _initparams {
    my $self = shift;

    $self->{from} = (@_ % 2) ? shift(@_) : undef;

    my %param = @_;
    $self->{from} = $param{from}
        if defined $param{from};

    foreach my $name (qw(error link)) {
        next unless defined $param{$name};
        croak "$name handler must be code"
            unless ref($param{$name}) and ref($param{$name}) eq 'CODE';
        $self->{$name.'_handler'} = $param{$name};
    }
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
    $self->{errorcount} = 0;
    $self->{lasterror} = [];
    $self->{lookaheadline} = undef;
    $self->{fh} = undef;
    $self->{inputlines} = [];
    $self->{examples} = [];

    return unless defined $self->{from};

    my $type = ref($self->{from});
    if ($type) {
        if ($type eq 'SCALAR') {
            $self->{inputlines} = [ split("\n",${$self->{from}}) ];
        } elsif ($type ne 'CODE') {
            $self->_handle_error( "Unknown input $type", 0, '' );
            return;
        }
    } elsif(!(open $self->{fh}, $self->{from})) {
        $self->_handle_error( 'Failed to open ' . $self->{from}, 0, '' );
        return;
    }

    # TODO: remove BOM (allowed in UTF-8)
    # /^\xEF\xBB\xBF/
    my $line = $self->_readline();
    return unless defined $line;

    do {
        $line =~ s/^\s+|\s*\n?$//g;
        if ($line eq '') {
            $self->{line}++;
        } elsif ($line =~ /^#([^:=\s]+)(\s*[:=]?\s*|\s+)(.*)$/) {
            $self->{line}++;
            $self->meta($1,$3); # TODO: check for errors and handle them?
        } else {
            $self->{lookaheadline} = $line;
            return;
        }
        $line = $self->_readline();
    } while (defined $line);
}

=head2 _handle_error ( $msg, $lineno, $line )

Internal error handler that calls a custom error handler,
increases the error counter and stores the last error. 

=cut

sub _handle_error {
    my $self = shift;
    $self->{lasterror} = [ @_ ];
    $self->{errorcount}++;
    $self->{error_handler}->( @_ ) if $self->{error_handler};
}

=head2 _readline

Internally read a line for parsing. May trigger an error.

=cut

sub _readline {
    my $self = shift;
    if ($self->{fh}) {
        return eval { no warnings; readline $self->{fh} };
    } elsif (ref($self->{from}) && ref($self->{from}) eq 'CODE') {
        my $line = eval { $self->{from}->(); };
        if ($@) { # input handler died
#print "L: $@";
            $self->_handle_error( $@, $self->{lineno}, '' );
            $self->{from} = undef;
        }
        return $line;
    } else {
        return @{$self->{inputlines}} ? shift(@{$self->{inputlines}}) : undef;
    }
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
