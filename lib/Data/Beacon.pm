package Data::Beacon;

use strict;
use warnings;

=head1 NAME

Data::Beacon - BEACON format validating parser and serializer

=cut

use Data::Validate::URI qw(is_uri);
use Time::Piece;
use Carp;

our $VERSION = '0.20';

use base 'Exporter';
our @EXPORT_OK = qw(getbeaconlink parsebeaconlink);

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

=head2 PARSING

You can parse BEACON from a file this way, using a link handler callback:

  my $beacon = new SeeAlso::Beacon( $filename );
  $beacon->parse( 'link' => \link_handler );
  $errors = $beacon->errorcount;

Alternatively you can use the parser as iterator:

  my $beacon = new SeeAlso::Beacon( $filename );
  while (my $link = $beacon->nextlink()) {
      if (ref($link)) {
          my ($id, $label, $description, $to, $fullid, $fulluri) = @$link;
      } else {
          my $error = $link;
      }
  }

Instead of a filename, you can also provide a scalar reference, to parse
from a string.

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
              # TODO: transform deprecated $PND etc.?
              $value =~ s/{id}/{ID}/g;
              $value =~ s/{label}/{LABEL}/g;
              croak 'Invalid #TARGET field: must contain {ID} or {LABEL}'
                  unless $value =~ /{ID}|{LABEL}/;
              my $uri = $value; 
              $uri =~ s/{ID}|{LABEL}//g;
              croak 'Invalid #TARGET field: must be an URI pattern'
                  unless is_uri($uri);
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
                    # Note that this conversion does not trigger an error
                    # or warning, but may be dropped in a future version
                } else {
                    croak $key . ' meta value must be of form YYYY-MM-DDTHH:MM:SS'
                        unless $value = Time::Piece->strptime( $value, 
                                                               '%Y-%m-%dT%T' );
                    $value = $value->datetime();
                }
            } elsif ( $key eq 'FORMAT' ) {
                croak 'Invalid FORMAT, must be BEACON or end with -BEACON'
                    unless $value =~ /^([A-Z]+-)?BEACON$/;
            } elsif ( $key eq 'EXAMPLES' ) {
                my @examples = map { s/^\s+|\s+$//g; $_ } split '\|', $value;
                $self->{examples} = [ grep { $_ ne '' } @examples ];
                %{$self->{expected_examples}} = 
                    map { $_ => 1 } @{$self->{examples}};
                $value = join '|', @{$self->{examples}};
                if ($value eq '') { # yet another edge case: "EXAMPLES: |" etc.
                    delete $self->{meta}->{EXAMPLES};
                    $self->{expected_examples} = undef;
                    next;
                }
                # Note that examples are not checked for validity,
                # because PREFIX may not be set yet.
            } elsif ( $key eq 'COUNT' ) {
                $self->{expected_count} = $value;
            }
            $self->{meta}->{$key} = $value;
        }
    }
}

=head2 count

If parsing has been started, returns the number of links, successfully read so
far (or zero). If only the meta fields have been parsed, this returns the value
of the meta field. In contrast to C<meta('count')>, this method always returns
a number. Note that all valid links that could be parsed are included, no matter
if processed by a link handler or not.

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

Return all meta fields, serialized and sorted as string. Althugh the order of
fields is irrelevant, but this implementation always returns the same fields
in same order.

=cut

sub metafields {
    my $self = shift;
    my %meta = $self->meta();
    my %fields = %meta;

    # determine default order
    my @order = qw(FORMAT PREFIX TARGET FEED CONTACT INSTITUTION DESCRIPTION
        TIMESTAMP UPDATE REVISIT MESSAGE ONEMESSAGE SOMEMESSAGE REMARK);
    delete $fields{$_} foreach @order;
    push @order, grep { !($_ =~ /^(EXAMPLES|COUNT)$/) } sort keys %fields;
    push @order, qw(EXAMPLES COUNT);

    my @lines = map { "#$_: " . $meta{$_} } grep { defined $meta{$_} } @order;
    return @lines ? join ("\n", @lines) . "\n" : "";
}

=head2 parse ( [ $from ] { handler => coderef } )

Parse all remaining links (push parsing). If provided a C<from> parameter,
this starts a new Beacon. That means the following three are equivalent:

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

 ( $id, $label, $description, $to, $fullid, $fulluri )

Please note that C<$label>, C<$description>, and C<$to> may be the empty
string, while C<$fullid> and C<$fulluri> are URIs.

The number of sucessfully parsed links is returned by C<count>.

Errors in link handler and input handler are catched, and produce an
error that is given to the error handler.

=cut

sub parse {
    my $self = shift;

    $self->_initparams( @_ );
    $self->_startparsing if defined $self->{from}; # start from new source

    $self->{meta}->{COUNT} = 0;
    my $line = $self->{lookaheadline};
    $line = $self->_readline() unless defined $line;

    while (defined $line) {
        $self->_parseline( $line );
        $line = $self->_readline();
    } 

    # additional integrity checks
    if (defined $self->{expected_count}) {
        if ($self->count != $self->{expected_count}) {
            my $msg = "expected " . $self->{expected_count} 
                    . " links, but got " . $self->count;
            $self->_handle_error( $msg, $self->{line}, '' );
        }
    }
    if (defined $self->{expected_examples}) {
        if (keys %{ $self->{expected_examples} }) {
            my $msg = 'examples not found: '
                    . join '|', keys %{ $self->{expected_examples} };
            $self->_handle_error( $msg, $self->{line}, '' );
        }
    }

    return $self->errorcount == 0;
}

=head2 nextlink

Read the input stream until the next link and return it (pull parsing).
Returns an array reference for a valid link, or undef after end of parsing.
This method skips over empty lines and errors, but calls error and link
handler, if enabled.

=cut

sub nextlink {
    my $self = shift;

    my $line = $self->{lookaheadline};
    if (defined $line) {
        $self->{lookaheadline} = undef;
    } else {
        $line = $self->_readline();
        return unless defined $line; # undef => EOF
    }

    do {
        my $link = $self->_parseline( $line );
        return $link if ref($link) and @$link; # non-empty array => link
        # proceed on empty lines or errors 
    } while($line = $self->_readline());

    return undef; # undef => EOF
}


=head1 FUNCTIONS

The following functions can be exported on request.

=head2 parsebeaconlink ( $line [, $target ] )

Parses a line, interpreted as link in BEACON format. Unless a target parameter
is given, the last part of the line is used as link destination, if it looks 
like an URI.

Returns an array reference with four values on success, an empty array reference for empty linkes, an error string on failure, or undef is the supplied line was
not defined. This method does not check whether the query identifier is a valid
URI, because it may be expanded by a prefix.

=cut

sub parsebeaconlink {
    my ($line, $target) = @_;

    return unless defined $line;

    my @parts = map { s/^\s+|\s+$//g; $_ } split('\|',$line);
    my $n = @parts;
    return [] if ($n < 1 || $parts[0] eq '');
    return "found too many parts (>4), divided by '|' characters" if $n > 4;
    my $link = [shift @parts,"","",""];

    if ($target) {
        $link->[1] = shift @parts if @parts;
        $link->[2] = shift @parts if @parts;
        # TODO: do we want both #TARGET links and explicit links in one file?
        $link->[3] = shift @parts if @parts;
    } else {
        $link->[3] = pop @parts
            if ($n > 1 && is_uri($parts[$n-2]));
        $link->[1] = shift @parts if @parts;
        $link->[2] = shift @parts if @parts;
    }

    return 'URI part has not valid URI form' if @parts; 

    return $link;
}

=head2 getbeaconlink ( $id, $label, $description, $to )

Serialize a link and return it as condensed string. You must provide four
parameters as string, which all can be the empty string. 'C<|>' characters
are silently removed. If the C<$to> is not empty but not an URI, or on other errors, the empty string is returned. The C<$id> parameter is not checked
whether it is an URI because it may be abbreviated (without PREFIX).

=cut

sub getbeaconlink {
    return if @_ < 4;
    my @link = @_[0 .. 3]; 
    @link = map { s/\|//g; $_; } @link;
    return '' if $link[0] eq '';

    if ( $link[3] eq '' ){
        pop @link;
        if ($link[2] eq '') {
            pop @link;
            pop @link if ($link[1] eq '');
        }
    } elsif ( is_uri($link[3]) ) {
        my $uri = pop @link;
        if ($link[2] eq '') {
           pop @link;
           pop @link if ($link[1] eq '');
        }
        push @link, $uri;
    } else {
        return "";
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

    # decide where to parse from
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

    # start parsing
    my $line = $self->_readline();
    return unless defined $line;
    $line =~ s/^\xEF\xBB\xBF//; # UTF-8 BOM (optional)

    do {
        $line =~ s/^\s+|\s*\n?$//g;
        if ($line eq '') {
            $self->{line}++;
        } elsif ($line =~ /^#([^:=\s]+)(\s*[:=]?\s*|\s+)(.*)$/) {
            $self->{line}++;
            eval { $self->meta($1,$3); };
            if ($@) {
                my $msg = $@; $msg =~ s/ at .*$//;
                $self->_handle_error( $msg, $self->{line}, $line );
            }
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

Internally read and return a line for parsing afterwards. May trigger an error.

=cut

sub _readline {
    my $self = shift;
    if ($self->{fh}) {
        return eval { no warnings; readline $self->{fh} };
    } elsif (ref($self->{from}) && ref($self->{from}) eq 'CODE') {
        my $line = eval { $self->{from}->(); };
        if ($@) { # input handler died
            $self->_handle_error( $@, $self->{lineno}, '' );
            $self->{from} = undef;
        }
        return $line;
    } else {
        return @{$self->{inputlines}} ? shift(@{$self->{inputlines}}) : undef;
    }
}

=head2 _parseline ( $line )

Internally parse a line and call appropriate handlers etc.
Returns a link as array reference, or an error message as string.

=cut

sub _parseline {
    my ($self, $line) = @_;

    $self->{line}++;
    my $link = parsebeaconlink( $line, $self->{meta}->{TARGET} );

    if (!ref($link)) {
        $self->_handle_error( $link, $self->{line}, $line );
        return $link;
    } 

    return $link unless @$link; # empty line or comment

    my $fullid = $link->[0];
    my $prefix = $self->{meta}->{PREFIX};
    $fullid = $prefix . $fullid if defined $prefix;

    if ( !is_uri($fullid) ) {
        $link = "id must be URI: $fullid";
        $self->_handle_error( $link, $self->{line}, $line );
        return $link;
    }

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
    if ( !is_uri($fulluri) ) {
        $link = "URI invalid: $fulluri";
        $self->_handle_error( $link, $self->{line}, $line );
        return $link;
    }

    # Finally we got a valid link

    $self->{meta}->{COUNT}++;

    if ( defined $self->{expected_examples} ) { # examples may contain prefix
        my @idforms = $link->[0];
        push @idforms, $prefix . $link->[0] if defined $prefix;
        foreach my $id (@idforms) {
            if ( $self->{expected_examples}->{$id} ) {
                delete $self->{expected_examples}->{$id};
                $self->{expected_examples} = undef 
                    unless keys %{ $self->{expected_examples} };
            }
        }
    }

    # expand link
    push @$link, $fullid;
    push @$link, $fulluri;

    if ($self->{link_handler}) {
        eval { $self->{link_handler}->( @$link ); };
        $self->_handle_error( "link handler died: $@", $self->{line}, $line )
            if $@;
    }

    return $link;
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
