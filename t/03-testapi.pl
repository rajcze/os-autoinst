#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 14;
use Test::Output;
use Test::Fatal;

BEGIN {
    unshift @INC, '..';
}

require bmwqemu;
require t::test_driver;

$bmwqemu::backend = t::test_driver->new;

use testapi;

my $cmd = 't::test_driver::type_string';
type_string 'hallo';
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', 4;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 4, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1, max_interval => 10;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 10, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

$testapi::password = 'stupid';
type_password;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 100, text => 'stupid'}]);
$bmwqemu::backend->{cmds} = [];

type_password 'hallo';
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 100, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

is($autotest::current_test->{dents}, undef, 'no soft failures so far');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents}, 1, 'soft failure recorded');
stderr_like(sub { record_soft_failure('workaround for bug#1234') }, qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason');
is($autotest::current_test->{dents}, 2, 'another');

# assert_script_run
{
    use autotest;
    $testapi::serialdev = 'null';
    {
        package t::test;

        sub new {
            my ($class) = @_;
            my $hash = {script => 'none'};
            return bless $hash, $class;
        }

        sub record_serialresult {
            my ($self) = @_;
        }
    }
    $autotest::current_test = t::test->new();

    require distribution;
    testapi::set_distribution(distribution->new());
    # TODO these tests call 'wait_serial' internally which causes a delay of 1 second each which is not so nice for testing
    is(assert_script_run('true'), undef, 'nothing happens on success');
    like(exception { assert_script_run 'false'; }, qr/command.*false.*failed at/, 'dies with standard message');
    like(exception { assert_script_run 'false', 0, 'my custom fail message'; }, qr/command.*false.*failed: my custom fail message at/, 'custom message on die');
}

# vim: set sw=4 et:
