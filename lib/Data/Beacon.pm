package Data::Beacon;

use strict;
use warnings;

=head1 NAME

Data::Beacon - BEACON format validating parser and serializer

=cut

use Time::Piece;
use Scalar::Util qw(blessed);
use URI::Escape;
use Carp;

our $VERSION = '0.2.4';

use base 'Exporter';
our @EXPORT = qw(plainbeaconlink parsebeaconlink beacon);

=head1 SYNOPSIS

  use Data::Beacon;

  $beacon = new SeeAlso::Beacon( $beaconfile );
  $beacon = beacon( $beaconfile ); # equivalent

  $beacon = beacon( { FOO => "bar" } ); # empty Beacon with meta fields

  $beacon->meta();                                   # get all meta fields
  $beacon->meta( 'DESCRIPTION' => 'my best links' ); # set meta fields
  $d = $beacon->meta( 'DESCRIPTION' );               # get meta field
  $beacon->meta( 'DESCRIPTION' => '' );              # unset meta field
  print $beacon->metafields();

  $beacon->parse(); # proceed parsing links

  $beacon->parse( error => 'print' );          # print errors to STDERR
  $beacon->parse( error => \&error_handler );

  $beacon->parse( $beaconfile );
  $beacon->parse( \$beaconstring );
  $beacon->parse( sub { return $nextline } );

  $beacon->count();      # number of parsed links
  $beacon->errorcount(); # number of parsing errors

=head1 DESCRIPTION

This package implements a parser and serializer for BEACON format with
dedicated error handling. A B<Beacon>, as implemente by C<Data::Beacon>
is I<a set of links> together with some I<meta fields> that describe it.
Each link consists of four values I<source> (also refered to as I<id>),
I<label>, I<description>, and I<target>, where source and target are
mandatory URIs, and label and description are strings, being the empty 
string by default.

B<BEACON format> is the serialization format for Beacons. It defines a
very condense syntax to express links without having to deal much with
technical specifications.

See L<http://meta.wikimedia.org/wiki/BEACON> for a more detailed  description.

=head2 SERIALIZING

To serialize only BEACON meta fields, create a new Beacon object, and set its
meta fields (passed to the constructor, or with L</meta>). You can then get 
the meta fields in BEACON format with L</metafields>:

  my $beacon = beacon( { PREFIX => ..., TARGET => ... } );
  print $beacon->metafields;

The easiest way to serialize links in BEACON format, is to set your Beacon 
object's link handler to C<print>, so each link is directly printed to STDOUT.
By setting the error handler also to C<print>, errors are printed to STDERR.

  my $beacon = beacon( \%metafields, errors => 'print', links => 'print' );
  print $b->metafields();

  while ( ... ) {
      $beacon->appendlink( $source, $label, $description, $target );
  }

Alternatively you can use the function L</plainbeaconlink>. In this case you
should validate links before printing:

  if ( $beacon->appendlink( $source, $label, $description, $target ) ) {
      print plainbeaconlink( $beacon->lastlink ) . "\n";
  }

=head2 PARSING

You can parse BEACON format either as iterator:

  my $beacon = beacon( $file );
  while ( $beacon->nextlink() ) {
      my ($source, $label, $description, $target, $sourceuri, $targeturi) = @{$beacon->lastlink};
      ...
  }

Or by push parsing with handler callbacks:

  my $beacon = beacon( $file );
  $beacon->parse( 'link' => \link_handler );
  $errors = $beacon->errorcount;


Instead of a filename, you can also provide a scalar reference, to parse
from a string. The meta fields are parsed immediately:

  my $beacon = beacon( $file );
  print $beacon->metafields . "\n";
  my $errors = $beacon->errorcount;

To quickly parse a BEACON file:

  use Data::Beacon;
  beacon($file)->parse();

=head2 QUERYING



=head1 METHODS

=head2 new ( [ $from ] { handler => coderef } | $metafields )

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

sub meta { # TODO: document meta fields
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
        $value =~ s/^\s+|\s+$|\n//g;
        if ($value eq '') { # empty field: unset
            croak 'You cannot unset meta field #FORMAT' if $key eq 'FORMAT';
            delete $self->{meta}->{$key};
        } else { # check format of known meta fields
            if ($key eq 'TARGET') {
                # TODO: transform deprecated $PND etc.?
                $value =~ s/{id}/{ID}/g;
                $value =~ s/{label}/{LABEL}/g;
                # TODO: document that {ID} in target is optional (will be appended)
                $value .= '{ID}' unless $value =~ /{ID}|{LABEL}/; 
                my $uri = $value; 
                $uri =~ s/{ID}|{LABEL}//g;
                croak 'Invalid #TARGET field: must be an URI pattern'
                    unless _is_uri($uri);
            } elsif ($key eq 'FEED') {
                croak 'FEED meta value must be a HTTP/HTTPS URL' 
                    unless $value =~ 
  /^http(s)?:\/\/[a-z0-9-]+(.[a-z0-9-]+)*(:[0-9]+)?(\/[^#|]*)?(\?[^#|]*)?$/i;
            } elsif ($key eq 'PREFIX') {
                croak 'PREFIX meta value must be a URI' 
                    unless _is_uri($value);
            } elsif ($key eq 'TARGETPREFIX') {
                croak 'TARGETPREFIX meta value must be a URI' 
                    unless _is_uri($value);
            } elsif ( $key =~ /^(REVISIT|TIMESTAMP)$/) {
                if ($value =~ /^[0-9]+$/) { # seconds since epoch
                    $value = gmtime($value)->datetime() . 'Z'; 
                    # Note that this conversion does not trigger an error
                    # or warning, but may be dropped in a future version
                } else {
                    # ISO 8601 combined date and time in UTC
                    $value =~ s/Z$//;
                    croak $key . ' meta value must be of form YYYY-MM-DDTHH:MM:SSZ'
                        unless $value = Time::Piece->strptime( 
                            $value, '%Y-%m-%dT%T' );
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
            if ((defined $self->{meta}->{TARGET} and $key eq 'TARGETPREFIX') 
              ||(defined $self->{meta}->{TARGETPREFIX} and $key eq 'TARGET')) {
                croak "TARGET and TARGETPREFIX cannot be set both";
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

Returns the current line number or zero.

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
in same order. To get all meta fields as hash, use the C<meta> method.

=cut

sub metafields {
    my $self = shift;
    my %meta = $self->meta();
    my %fields = %meta;

    # determine default order
    my @order = 
      qw(FORMAT PREFIX TARGET TARGETPREFIX FEED CONTACT INSTITUTION DESCRIPTION
         TIMESTAMP UPDATE REVISIT MESSAGE ONEMESSAGE SOMEMESSAGE REMARK);
    delete $fields{$_} foreach @order;
    push @order, grep { !($_ =~ /^(EXAMPLES|COUNT)$/) } sort keys %fields;
    push @order, qw(EXAMPLES COUNT);

    my @lines = map { "#$_: " . $meta{$_} } grep { defined $meta{$_} } @order;
    return @lines ? join ("\n", @lines) . "\n" : "";
}

=head2 parse ( [ $from ] { handler => coderef | option => $value } )

Parse all remaining links (push parsing). If provided a C<from> parameter,
this starts a new Beacon. That means the following three are equivalent:

  $b = new SeeAlso::Beacon( $from );

  $b = new SeeAlso::Beacon( from => $from );

  $b = new SeeAlso::Beacon;
  $b->parse( $from );

If C<from> is a scalar, it is used as file to parse from. Alternatively you
can supply a string reference, or a code reference.

The C<pre> option can be used to set some meta fields before parsing starts.
These fields are cached and reused every time you call C<parse>.

If the C<mtime> option is given, the TIMESTAMP meta value will be initialized
as last modification time of the given file.

By default, all errors are silently ignored, unless you specifiy an C<error>
handler. The last error can be retrieved with the C<lasterror> method and the
number of errors by C<errorcount>. Returns true only if C<errorcount> is zero 
after parsing. Note that some errors may be less important.

Finally, the C<link> handler can be a code reference to a method that is
called for each link (that is each line in the input that contains a valid
link). The following arguments are passed to the handler:

=over

=item C<$source>

Link source as given in BEACON format.
This may be abbreviated but not the empty string.

=item C<$label>

Label as string. This may be the empty string.

=item C<$description>

Description as string. This may be the empty string.

=item C<$target>

Link target as given in BEACON format.
This may be abbreviated or the empty string.

=item C<$sourceuri>

Expanded link source as URI.

=item C<$targeturi>

Expanded link target as URI.

=back

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
        $self->appendline( $line );
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

Read from the input stream until the next link has been parsed. Empty lines
and invalid lines are skipped, but the error handler is called on invalid 
lines. This method can be used for pull parsing. It eithe returns a link
as array reference, or undef if the end of input has been reached.

=cut

sub nextlink {
    my $self = shift;

    my $line = $self->{lookaheadline};
    if (defined $line) {
        $self->{lookaheadline} = undef;
    } else {
        $line = $self->_readline();
        return undef unless defined $line; # undef => EOF
    }

    do {
        # proceed on empty lines or errors 
        return $self->{lastlink} 
            if defined $self->appendline( $line );
    } while($line = $self->_readline());

    return undef; # undef => EOF
}

=head2 lastlink

Returns the last valid link that has been read.

=cut

sub lastlink {
    my $self = shift;
    return $self->{lastlink};
}

=head2 appendline( $line )

Append a line of of BEACON format. This method parses the line, and calls the
link handler, or error handler. In scalar context returns whether a link has
been read (that can then be accessed with C<lastlink>). In list context, returns
the parsed link as array, or undef.

=cut

sub appendline {
    my ($self, $line) = @_;

    $self->{line}++;
    $self->{currentline} = $line;
    my @parts = split ('\|',$line);

    return if (@parts < 1 || $parts[0] eq '');
    my $has_link = $self->appendlink( @parts );
    $self->{currentline} = undef;

    if ( $has_link ) {
        return wantarray ? @{ $self->{lastlink} } : 1;
    }
}

=head2 appendlink ( $source [, $label [, $description [, $target ] ] ] )

Append a link. The link is validated. On error the error handler is called.
On success the link handler is called. In scalar context returns whether the
link was valid. In list context returns the link on success.

=cut

sub appendlink {
    my $self = shift;

    my $n = scalar @_;
    my $msg = undef;

    if ( $n == 0 || $_[0] eq '' ) {
        $msg = "missing source";
    } elsif ( $n > 4 ) {
        $msg = "found too many parts (>4), divided by '|' characters";
    } elsif ( grep { $_ =~ /\|/ } @_ ) {
        $msg = "link parts must not contain '|'";
    }

    if ($msg) {
        $self->_handle_error( $msg, $self->{line} );
        return;
    }

    my @parts = @_;
    @parts = map { s/^\s+|\s+$//g; $_ } @parts; # trim
    my $link = [shift @parts,"","",""];

    my $target = $self->{meta}->{TARGET};
    my $targetprefix = $self->{meta}->{TARGETPREFIX};
    if ($target or $targetprefix) {
        $link->[1] = shift @parts if @parts;
        $link->[2] = shift @parts if @parts;
        # TODO: do we want both #TARGET links and explicit links in one file?
        $link->[3] = shift @parts if @parts;
    } else {
        $link->[3] = pop @parts
            if ($n > 1 && _is_uri($parts[$n-2]));
        $link->[1] = shift @parts if @parts;
        $link->[2] = shift @parts if @parts;
    }

    if ( @parts ) {
        $self->_handle_error( 'URI part has no valid URI form: '.$parts[0], $self->{line} );
        return;
    } 

    return unless @$link; # empty line or comment

    my $sourceuri = $link->[0];
    my $prefix = $self->{meta}->{PREFIX};
    $sourceuri = $prefix . $sourceuri if defined $prefix;

    if ( !_is_uri($sourceuri) ) {
        $self->_handle_error( "source is no URI: $sourceuri", $self->{line} ); 
        return;
    }

    my $targeturi;
    if (defined $target) {
        $targeturi = $target;
        my ($source,$label) = ($link->[0], $link->[1]);
        $targeturi =~ s/{ID}/$source/g;
        $targeturi =~ s/{LABEL}/uri_escape($label)/eg;
    } elsif( defined $targetprefix ) {
        $targeturi = $targetprefix . $link->[3];
    } else {
        $targeturi = $link->[3];
    }
    if ( !_is_uri($targeturi) ) {
        # TODO: we could encode bad characters etc.
        $self->_handle_error( "invalid target URI: $targeturi", $self->{line} );
        return;
    }

    # Finally we got a valid link
    $self->{lastlink} = $link;
    $self->{meta}->{COUNT}++;

    if ( defined $self->{expected_examples} ) { # examples may contain prefix
        my @idforms = $link->[0];
        push @idforms, $prefix . $link->[0] if defined $prefix;
        foreach my $source (@idforms) {
            if ( $self->{expected_examples}->{$source} ) {
                delete $self->{expected_examples}->{$source};
                $self->{expected_examples} = undef 
                    unless keys %{ $self->{expected_examples} };
            }
        }
    }

    # expand link
    push @$link, $sourceuri;
    push @$link, $targeturi;

    if ($self->{link_handler}) {
        if ( $self->{link_handler} eq 'print' ) {
           print plainbeaconlink( @$link ) . "\n";
         } elsif ( $self->{link_handler} eq 'expand' ) { 
            # TODO
         } else {
            eval { $self->{link_handler}->( @$link ); };
            if ( $@ ) {
                $self->_handle_error( "link handler died: $@", $self->{line} );
                return;
            }
        }
    }

    return wantarray ? @$link : 1; # TODO: return expanded link instead?
}

=head2 expandlink ( $source, $label, $description, $target )

Expand a link, consisting of source (mandatory), and label, description,
and target (all optional). Returns the expanded link as array with four 
values, or undef.

=cut

sub expandlink {
    my $self = shift;
    my ($id, $label, $description, $to, $fullid, $fulluri) = @_;

    # TODO: error handling
    # TODO: get fullid and fulluri by expansion and test this method

    my @link = $fullid;
    push @link, $label if $label ne '' or $description ne '';
    push @link, $description if $description ne '';
    push @link, $fulluri;

    return @link;
}

=head1 FUNCTIONS

The following functions are exported by default.

=head2 beacon ( [ $from ] { handler => coderef } )

Shortcut for C<Data::Beacon-E<gt>new>.

=cut

sub beacon {
    return Data::Beacon->new( @_ );
}

=head2 parsebeaconlink ( $line [, $target ] )

Parses a line, interpreted as link in BEACON format. Unless a target parameter
is given, the last part of the line is used as link destination, if it looks 
like an URI. Returns an array reference with four values on success, an empty 
array reference for empty linkes, an error string on failure, or undef is the 
supplied line was not defined. This method does not check whether the query 
identifier is a valid URI, because it may be expanded by a prefix.

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
            if ($n > 1 && _is_uri($parts[$n-2]));
        $link->[1] = shift @parts if @parts;
        $link->[2] = shift @parts if @parts;
    }

    return ('URI part has not valid URI form: ' . $parts[0]) if @parts; 

    return $link;
}

=head2 plainbeaconlink ( $source, $label, $description, $target )

Serialize a link, consisting of source (mandatory), and label, description,
and target (all optional) as condensed string in BEACON format. This function
does not check whether the arguments form a valid link or not!

=cut

sub plainbeaconlink {
    shift if ref($_[0]) and UNIVERSAL::isa($_[0],'Data::Beacon');
    return '' unless @_; 
    my @link = map { defined $_ ? $_ : '' } @_[0..3];
    @link = map { s/^\s+|\s+$//g; $_; } @link;
    return '' if $link[0] eq '';

    if ( $link[3] eq '' ){
        pop @link;
        if ($link[2] eq '') {
            pop @link;
            pop @link if ($link[1] eq '');
        }
    } elsif ( _is_uri($link[3]) ) { # only position of _is_uri where argument may be undefined
        my $uri = pop @link;
        if ($link[2] eq '') {
           pop @link;
           pop @link if ($link[1] eq '');
        }
        push @link, $uri;
    }

    return join('|', @link);
}

=head1 INTERNAL METHODS

If you directly call any of this methods, puppies will die.

=head2 _initparams ( [ $from ] { handler => coderef | option => value } | $metafield )

Initialize parameters as passed to C<new> or C<parse>. Known parameters
are C<from>, C<error>, and C<link> (C<from> is not checked here). In 
addition you cann pass C<pre> and C<mtime> as options.

=cut

sub _initparams {
    my $self = shift;
    my %param;

    if ( @_ % 2 && !blessed($_[0]) && ref($_[0]) && ref($_[0]) eq 'HASH' ) {
        my $pre = shift;
        %param = @_;
        $param{pre} = $pre;
    } else {
        $self->{from} = (@_ % 2) ? shift(@_) : undef;
        %param = @_;
    }

    $self->{from} = $param{from}
        if exists $param{from};

    foreach (qw(errors links)) {
        my $hdl = $param{$_} || next;
        my $name = $_;
        $name =~ s/s$//;
        croak "$name handler must be code"
            unless $hdl eq 'print' or (ref($hdl) and ref($hdl) eq 'CODE');
        if ( $name eq 'error' and $hdl eq 'print' ) {
           $hdl = sub {
              my ($msg, $lineno) = @_;
              $msg .= " at line $lineno" if defined $lineno;
              print STDERR "$msg\n";
           };
        }
        $self->{$name.'_handler'} = $hdl;
    }

    if ( defined $param{pre} ) {
        croak "pre option must be a hash reference"
            unless ref($param{pre}) and ref($param{pre}) eq 'HASH';
        $self->{pre} = $param{pre};
    } elsif ( exists $param{pre} ) {
        $self->{pre} = undef;
    }

    $self->{mtime} = $param{mtime};
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

    # we do not init $self->{meta} because it is set in initparams;
    $self->{meta} = { 'FORMAT' => 'BEACON' };
    $self->meta( %{ $self->{pre} } ) if $self->{pre};
    $self->{line} = 0;
    $self->{lastlink} = undef;
    $self->{errorcount} = 0;
    $self->{lasterror} = [];
    $self->{lookaheadline} = undef;
    $self->{fh} = undef;
    $self->{inputlines} = [];
    $self->{examples} = [];
    $self->{expected_count} = undef;

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
    } elsif( $self->{from} eq '-' ) {
        $self->{fh} = \*STDIN;
    } else {
        if(!(open $self->{fh}, $self->{from})) {
            $self->_handle_error( 'Failed to open ' . $self->{from}, 0, '' );
            return;
        }
    }

    # initlialize TIMESTAMP
    if ($self->{mtime}) {
        my @stat = stat( $self->{from} );
        $self->meta('TIMESTAMP', gmtime( $stat[9] )->datetime() . 'Z' );
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

=head2 _handle_error ( $msg, $lineno [, $line ] )

Internal error handler that calls a custom error handler,
increases the error counter and stores the last error. 

=cut

sub _handle_error {
    my $self = shift;
    my ( $msg, $lineno, $line ) = @_;
    $line = $self->{currentline} unless defined $line;
    $self->{lasterror} = [ $msg, $lineno, $line ];
    $self->{errorcount}++;
    $self->{error_handler}->( $msg, $lineno, $line ) if $self->{error_handler};
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

=head2 _is_uri

Check whether a given string is an URI. This function is based on code of
L<Data::Validate::URI>, adopted for performance.

=cut

sub _is_uri {
    my $value = $_[0];
    
    return unless defined($value);
    
    # check for illegal characters
    return if $value =~ /[^a-z0-9\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\.\-\_\~\%]/i;
    
    # check for hex escapes that aren't complete
    return if $value =~ /%[^0-9a-f]/i;
    return if $value =~ /%[0-9a-f](:?[^0-9a-f]|$)/i;
    
    # split uri (from RFC 3986)
    my($scheme, $authority, $path, $query, $fragment)
      = $value =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;

    # scheme and path are required, though the path can be empty
    return unless (defined($scheme) && length($scheme) && defined($path));
    
    # if authority is present, the path must be empty or begin with a /
    if(defined($authority) && length($authority)){
        return unless(length($path) == 0 || $path =~ m!^/!);    
    } else {
        # if authority is not present, the path must not start with //
        return if $path =~ m!^//!;
    }
    
    # scheme must begin with a letter, then consist of letters, digits, +, ., or -
    return unless lc($scheme) =~ m!^[a-z][a-z0-9\+\-\.]*$!;
    
    return 1;
}

1;

__END__

=head1 DEVELOPMENT

Please visit http://github.com/nichtich/p5-data-beacon for the latest
development snapshot, bug reports, feature requests, and such.

=head1 SEE ALSO

See also L<SeeAlso::Server> for an API to exchange single sets of 
beacon links, based on the same source identifier.

=head1 AUTHOR

Jakob Voss C<< <jakob.voss@gbv.de> >>

=head1 LICENSE

Copyright (C) 2010 by Verbundzentrale Goettingen (VZG) and Jakob Voss

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.

In addition you may fork this library under the terms of the 
GNU Affero General Public License.
