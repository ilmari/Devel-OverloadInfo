package Devel::OverloadInfo;

use strictures 1;
use overload ();
use Scalar::Util qw(blessed);
use Sub::Identify qw(sub_fullname);
use Package::Stash;
use if $] < 5.009005, 'MRO::Compat';
use if $] >= 5.009005, 'mro';

use Exporter qw(import);
our @EXPORT_OK = qw(overload_info);

sub stash_with_symbol {
    my ($class, $symbol) = @_;

    for my $package (@{mro::get_linear_isa($class)}) {
        my $stash = Package::Stash->new($package);
        my $value_ref = $stash->get_symbol($symbol);
        return ($stash, $value_ref) if $value_ref;
    }
    return;
}

sub overload_info {
    my $class = blessed($_[0]) || $_[0];

    return undef unless overload::Overloaded($class);

    my (%overloaded);
    for my $op (map split(/\s+/), values %overload::ops) {
        my $op_method = $op eq 'fallback' ? "()" : "($op";
        my ($stash, $func) = stash_with_symbol($class, "&$op_method")
            or next;
        my $info = $overloaded{$op} = {
            class => $stash->name,
        };
        if ($func == \&overload::nil) {
            # Named method or fallback, stored in the scalar slot
            if (my $value_ref = $stash->get_symbol("\$$op_method")) {
                my $value = $$value_ref;
                if ($op eq 'fallback') {
                    $info->{value} = $value;
                } else {
                    $info->{method_name} = $value;
                    if (my ($impl_stash, $impl_func) = stash_with_symbol($class, "&$value")) {
                        $info->{code_class} = $impl_stash->name;
                        $info->{code} = $impl_func;
                    }
                }
            }
        } else {
            $info->{code} = $func;
        }
        $info->{code_name} = sub_fullname($info->{code})
            if exists $info->{code};
    }
    return \%overloaded;
}

1;
