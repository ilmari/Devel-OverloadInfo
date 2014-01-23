#!/usr/bin/env perl
use strictures 1;
use Test::More 0.88;

use Devel::OverloadInfo qw(overload_info);

sub MyModule::negate { -$_[0] }

my $num_sub;
BEGIN { $num_sub = sub { 0 } };
{
    package BaseClass;
    use overload (
        '""' => 'stringify',
        bool => 'boolify',
        '0+' => $num_sub,
    );

    sub boolify { 1 }
}

{
    package ChildClass;
    use parent -norequire => 'BaseClass';

    use overload (
        neg => \&MyModule::negate,
        fallback => 1,
    );

    sub stringify { "foo" }
}

my $boi = overload_info('BaseClass');

# Whether undef fallback exists varies between perl versions
if (my $fallback = delete $boi->{fallback}) {
    is_deeply $fallback, {
        class => 'BaseClass',
        value => undef,
    }, 'BaseClass fallback is undef';
}

is_deeply $boi,
    {
        '""' => {
            class => 'BaseClass',
            method_name => 'stringify',
        },
        bool => {
            class => 'BaseClass',
            method_name => 'boolify',
            code_class => 'BaseClass',
            code => \&BaseClass::boolify,
            code_name => "BaseClass::boolify",
        },
        '0+' => {
            class => 'BaseClass',
            code => $num_sub,
            code_name => 'main::__ANON__',
        },
    },
    "BaseClass overload info" or note explain $boi;

my $coi = overload_info('ChildClass');

is_deeply $coi,
    {
        fallback => {
            class => 'ChildClass',
            value => 1,
        },
        '""' => {
            class => 'BaseClass',
            method_name => 'stringify',
            code_class => 'ChildClass',
            code => \&ChildClass::stringify,
            code_name => 'ChildClass::stringify',
        },
        bool => {
            class => 'BaseClass',
            method_name => 'boolify',
            code_class => 'BaseClass',
            code => \&BaseClass::boolify,
            code_name => "BaseClass::boolify",
        },
        '0+' => {
            class => 'BaseClass',
            code => $num_sub,
            code_name => 'main::__ANON__',
        },
        neg => {
            class => 'ChildClass',
            code => \&MyModule::negate,
            code_name => 'MyModule::negate',
        },
    },
    "ChildClass overload info" or note explain $coi;

done_testing;
