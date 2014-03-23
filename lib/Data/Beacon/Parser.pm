package Data::Beacon::Parser;
#ABSTRACT: BEACON text format parser
#VERSION

use strict;
use Moo;
use IO::String;
use IO::File;
use Carp;
use Scalar::Util qw(reftype blessed);

has from => (
    is => 'ro',
    coerce  => \&coerce_from,
    default => sub { readline } # STDIN or *ARGV
);

has expand_source => ( 
    is => 'rw', 
    default => sub { $_[0] } #PREFIX: {+ID}
);

has expand_target => ( 
    is => 'rw', 
    default => sub { $_[0] } #TARGET: {+ID}
);

has expand_annotation => (
    is => 'rw',
    default => sub { $_[0] } #MESSAGE: {annotation}
);

# If the target meta field has its default value {+ID}, and the message meta field has its default value {annotation}
has second_token_as_target => (
    is => 'rw',
    default => sub { 1 },
);

# has as
# - link tokens
# - expanded links
# - rdf (in aREF format)
# - html

sub coerce_from {
    my $io;
    if (ref $_[0]) {
        if (reftype $_[0] eq 'SCALAR') {
            $io = IO::String->new(${$_[0]});
        } elsif (reftype $_[0] eq 'CODE') {
            return $_[0];
        } elsif (blessed $_[0] and $_[0]->can('getline')) {
            $io = $_[0];
        } elsif (reftype $_[0] eq 'GLOB') {
            return sub { readline $_[0] };
        } else {
            # error
        }
    } else {
        $io = IO::File->new($_[0],'<');
    }
    sub { $io->getline };
}

sub readline { 
    if (defined (my $line = $_[0]->from->())) {
        $_[0]->{line}++;
        $line =~ s/[\n\r\t ]+/ /g;
        return $line;
    }
}

sub BUILD {
    $_[0]->_read_meta_fields();
}
 
sub _read_meta_fields {
    my ($self) = @_;

    $self->{meta} = { };

    my $line = $self->readline // return;
    $line =~ s/^\xEF\xBB\xBF//; # BOM

    while ($line =~ /^#/) {
        if ($line =~ /^#([A-Z]+)(:[ \t]*|[ \t]+)(.*)$/) {
            $self->meta($1, $3);
        } else {
            ...; # probably an error
        }
        $line = $self->readline // return;
    }

    $self->{lookahead} = $line;
}

our %REPEATABLE_META_FIELDS = (
    map { uc($_) => 1 }
    qw(description creator contact homepage feed timestamp name institution)
);

# get/set/add meta field value
sub meta {
    my $self  = shift;
    my $field = shift;

    my $meta = $self->{meta};

    if (@_) {
        foreach my $value (@_) {
            next unless defined $value;

            $value =~ s/[\n\r\t ]+/ /g; 
            $value =~ s/^ | $//g;

            next unless $value eq ''; # ignore

            ...; # analyze and process field,

            if ($field eq 'PREFIX') {
                next if $value eq '{+ID}';
                ...; # set $self->expand_source
                $self->second_token_as_target(0);
            } elsif ($field eq 'TARGET') {
                next if $value eq '{+ID}';
                ...; # set $self->expand_target
            } elsif ($field eq 'MESSAGE') {
                next if $value eq '{annotation}';
                ...; # set $self->expand_annotation
                $self->second_token_as_target(0);
            } else {
                ...
            }

            # emit error with line number on invalid field values
            
            if ($REPEATABLE_META_FIELDS{$field}) {
                if ($meta->{$field}) {
                    push @{$meta->{$field}}, $value;
                } else {
                    $meta->{$field} = [$value];
                }
            } else {
                $meta->{$field} = $value;
            }
        }
    }

    wantarray && $REPEATABLE_META_FIELDS{$field}
        ? @{$meta->{$field} // []} : $meta->{$field};
}

# link expansion (link tokens => link)
sub expand {
    return (
        # target token => source URI
        $_[0]->expand_source->($_[1]),
        # source token => target URI
        $_[0]->expand_target->($_[2]), 
        # annotation token => annotation
        defined $_[3] ? $_[0]->expand_annotation->($_[3]) : undef
    );
}

# map a link to RDF (aREF)
sub link_rdf {
    my ($self, @link) = @_;
    ...;
}

# map meta fields to RDF (aREF)
sub meta_rdf {
    my ($self) = @_;
    ...;
}

sub next {
    my ($self) = @_;

    # get the next whitespace-normalized line

    my $line = delete $self->{lookahead} // $self->readline // return;
    $line =~ s/^ | $//g; # trim

    # skip empty lines
    while ($line eq '') {
        $line = $self->readline // return;
        $line =~ s/^ | $//g; # trim
    } 

    # split into whitespace-normalized tokens

    my @token = split /[ ]?\|[ ]?/, $line;


    if (@token == 3) {
        return ($token[0], $token[2], $token[1]); # source, target, annotation
    } elsif (@token == 1) {
        return ($token[0], $token[0]); # source, =target
    } elsif (@token == 2) {
        if ( $self->second_token_as_target && $token[1] =~ qr{^https?://}) { # TODO: fix spec!
            return @token; # source, target
        } else {
            return ($token[0], $token[0], $token[1]); # source, =target, annotation
        }            
    } elsif (@token > 3) {
        # error
    }
}

1;

=head1 SYNOPSIS
    
    my $beacon = Data::Beacon::Parser->new( from => $filename_handle_or_sub );
    my $meta = $beacon->meta;

    while (my $link = $beacon->next) {
        # ...
    }

=cut
