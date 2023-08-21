package CycloneDX::Parser;

# ABSTRACT: Parser for CycloneDX SBOMs

use v5.14.0;
use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Carp 'croak';
use JSON::PP 'decode_json';

our $VERSION = '0.01';

sub new ( $class, %arg_for ) {
    my $self = bless {}, $class;
    $self->_initialize(%arg_for);
    return $self;
}

sub _initialize ( $self, %arg_for ) {
    my $json = $arg_for{json} or croak 'No JSON provided';
    if ( ref $json ) {
        $json = $$json;
    }
    else {
        open my $fh, '<', $json or croak "Can't open $json: $!";
        $json = do { local $/; <$fh> };
    }
    $self->{json}   = decode_json($json);
    $self->{errors} = [];
    $self->_validate(
        keys => [
            [ 'bomFormat',   'CycloneDX' ],
            [ 'specVersion', '1.5' ],
            [ 'version',     qr/^[1-9][0-9]*$/ ],
        ],
        required => 1,
        source   => $self->sbom_spec,
    );
    $self->_validate(
        keys => [
            [ 'components', \&_validate_components ],
        ],
        source => $self->sbom_spec,
    );

    return $self;
}

sub is_valid ($self) {
    return !@{ $self->{errors} };
}

sub errors ($self) {
    return @{ $self->{errors} };
}

sub sbom_spec ($self) {
    return $self->{json};
}

sub _add_error ( $self, $error ) {
    push @{ $self->{errors} }, $error;
}

# Yes, this should use a JSON validator, but we need it to be lightweight
# and not require any non-core modules.
sub _validate ( $self, %arg_for ) {
    foreach my $key ( @{ $arg_for{keys} } ) {
        $self->_validate_key(
            inspect  => $arg_for{source},
            required => $arg_for{required},
            key      => $key->[0],
            matches  => $key->[1],
            name     => $key->[2],
        );
    }
}

sub _validate_key ( $self, %arg_for ) {
    my ( $data, $key, $required, $matches, $name ) = @arg_for{qw(inspect key required matches name)};
    $name ||= $key;
    if ( !exists $data->{$key} ) {
        if ($required) {
            $self->_add_error("Missing required field '$name'");
        }
        return;
    }
    my $value = $data->{$key};
    if ( !ref $matches ) {
        if ( $value ne $matches ) {
            $self->_add_error("Invalid $name. Must be '$matches', not '$value'");
        }
    }
    elsif ( ref $matches eq 'Regexp' ) {
        if ( $value !~ $matches ) {
            $self->_add_error("Invalid $name. Must match '$matches', not '$value'");
        }
    }
    elsif ( ref $matches eq 'ARRAY' ) {
        if ( !grep { $_ eq $value } @$matches ) {
            $self->_add_error("Invalid $name. Must be one of '@$matches', not '$value'");
        }
    }
    elsif ( ref $matches eq 'CODE' ) {
        $self->$matches($value);
    }
    else {
        croak "Invalid matches type: $matches";
    }
}

sub _validate_components ( $self, $components ) {
    unless ( ref $components eq 'ARRAY' ) {
        $self->_add_error('Components must be an array');
        return;
    }
    foreach my $component (@$components) {
        $self->_validate(
            keys => [
                [   'type',
                    [   "application", "framework", "library", "container", "platform", "operating-system", "device", "device-driver", "firmware", "file",
                        "machine-learning-model", "data",
                    ],
                    'component.type'
                ],
                [ 'name', qr/\S/, 'component.name' ],
            ],
            required => 1,
            source   => $component,
        );
        $self->_validate(
            keys => [
                [ 'version',   qr/\S/,                          'component.version' ],     # version not enforced
                [ 'mime-type', qr{^[-+a-z0-9.]+/[-+a-z0-9.]+$}, 'component.mime-type' ],
            ],
            source => $component,
        );
        if ( exists $component->{modified} ) {
            $self->_add_error('component.modified is deprecated and should not be used.');
        }
    }
}

1;

__END__

=head1 SYNOPSIS

        my $parser = CycloneDX::Parser->new( json => $file );
        if ( $parser->is_valid ) {
            my $data = $parser->sbom_spec;
        }
        else {
            my @errors = $parser->errors;
            ...
        }

=head1 DESCRIPTION

This module parses CycloneDX Software Bill of Materials (SBOMs), version 1.5
JSON. It is a work in progress.

Eventually earlier versions will be supported, but for now, trying to get it
working and seeing how the design evolves.
