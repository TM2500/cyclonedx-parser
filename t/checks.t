#!/usr/bin/env perl

use lib 'lib';
use v5.14.0;
use strict;
use warnings;
use experimental 'signatures';
use Test::More;
use CycloneDX::Parser::Checks ':all';
use CycloneDX::Parser;

sub parser ($json) {
    my $parser = CycloneDX::Parser->new( json_string => $json );
    $parser->_push_stack('test');
    return $parser;
}

my $json = <<'END';    # minimal valid SBOM
{
    "bomFormat": "CycloneDX",
    "specVersion": 1.5
}
END

subtest 'is_string simple string matching' => sub {
    ok my $is_foo = is_string('foo'), 'is_string($some_string) should succeed';
    is ref $is_foo, 'CODE', 'is_string() should return a subref';
    my $p = parser($json);
    ok $is_foo->( $p, 'foo' ),  'is_string() should return true if the string value exactly matches';
    ok $p->is_valid,            '... and we should have no errors';
    ok !$is_foo->( $p, 'bar' ), 'is_string() should return false if the value does not exactly match';
    ok !$p->is_valid,           '... and we should have errors';
    my @errors = $p->errors;
    is @errors, 1, '... and we should have one error';
    like $errors[0], qr/Must be 'foo', not 'bar'/, '... and the error should be the expected one';
};

subtest 'is_string regex matching' => sub {
    ok my $is_foo = is_string(qr/^[0-9]+$/), 'is_string($some_regex) should succeed';
    is ref $is_foo, 'CODE', 'is_string() should return a subref';
    my $p = parser($json);
    ok $is_foo->( $p, '123' ),  'is_string() should return true if the string value matches the regex';
    ok $p->is_valid,            '... and we should have no errors';
    ok !$is_foo->( $p, 'bar' ), 'is_string() should return false if the value does not exactly match';
    ok !$p->is_valid,           '... and we should have errors';
    my @errors = $p->errors;
    is @errors, 1, '... and we should have one error';
    like $errors[0], qr/Must match '[^']+', not 'bar'/, '... and the error should be the expected one';
};

subtest 'is_string enums' => sub {
    ok my $is_foo = is_string( [qw/red green blue/] ), 'is_string($some_arrayref) should succeed';
    is ref $is_foo, 'CODE', 'is_string() should return a subref';
    my $p = parser($json);
    ok $is_foo->( $p, 'red' ),  'is_string() should return true if the string value matches an element of the enum';
    ok $p->is_valid,            '... and we should have no errors';
    ok !$is_foo->( $p, 'bar' ), 'is_string() should return false if the value does not exactly match';
    ok !$p->is_valid,           '... and we should have errors';
    my @errors = $p->errors;
    is @errors, 1, '... and we should have one error';
    like $errors[0], qr/Must be one of '[^']+', not 'bar'/, '... and the error should be the expected one';
};

subtest 'is_object' => sub {
    my $object = {
        color => is_string( [qw/red green blue/] ),
        name  => is_string(qr/^[a-zA-Z ]+$/),
    };
    ok my $is_foo = is_object($object), 'is_object($some_hashref) should succeed';
    is ref $is_foo, 'CODE', 'is_object() should return a subref';
    my $p = parser($json);
    ok $is_foo->( $p, { color => 'red', name => 'foo' } ), 'is_object() should return true if the hashref value matches the schema';
    ok $p->is_valid,                                       '... and we should have no errors';
    ok $is_foo->( $p, { name => 'foo' } ),                 '... and keys can be optional';
    ok $p->is_valid,                                       '... and we should have no errors';
    ok !$is_foo->( $p, { name => '!!!' } ),                '... but they had better be the right keys';
    ok !$p->is_valid,                                      '... and we should have errors';

    my $p = parser($json);
    $is_foo = is_object( $object, ['color'] );

    ok $is_foo->( $p, { color => 'red', name => 'foo' } ), 'is_object() should return true if the hashref value matches the schema';
    ok $p->is_valid,                                       '... and we should have no errors';
    ok !$is_foo->( $p, { name => 'foo' } ),                '... but missing required keys should return false';
    ok !$p->is_valid,                                      '... and we should have errors';
    my @errors = $p->errors;
    is @errors, 1, '... and we should have one error';
    like $errors[0], qr/Missing required field 'test\.color'/, '... and the error should be the expected one';

    my $p = parser($json);
    $is_foo = is_object($object);
    ok !$is_foo->( $p, 'bar' ), 'is_object() should return false if the value does not exactly match';
    ok !$p->is_valid,           '... and we should have errors';
    @errors = $p->errors;
    is @errors, 1, '... and we should have one error';
    like $errors[0], qr/Value test must be an object/, '... and the error should be the expected one';
};

done_testing;
