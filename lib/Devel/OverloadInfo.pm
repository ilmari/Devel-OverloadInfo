package Devel::OverloadInfo;

# ABSTRACT: introspect overloaded operators

=head1 DESCRIPTION

Devel::OverloadInfo returns information about L<overloaded|overload>
operators for a given class (or object), including where in the
inheritance hierarchy the overloads are declared and where the code
implementing them is.

=cut

use strict;
use warnings;
use overload ();
use Scalar::Util qw(blessed);
use Package::Stash 0.14;
use MRO::Compat;

BEGIN {
    if (eval { require Sub::Util } && defined &Sub::Util::subname) {
        *subname = \&Sub::Util::subname;
    }
    else {
        require B;
        *subname = sub {
            my ($coderef) = @_;
            die 'Not a subroutine reference'
                unless ref $coderef;
            my $cv = B::svref_2object($coderef);
            die 'Not a subroutine reference'
                unless $cv->isa('B::CV');
            my $gv = $cv->GV;
            return undef
                if $gv->isa('B::SPECIAL');
            my $stash = $gv->STASH;
            my $package = $stash->isa('B::SPECIAL') ? '__ANON__' : $stash->NAME;
            return $package . '::' . $gv->NAME;
        };
    }
}


use Exporter 5.57 qw(import);
our @EXPORT_OK = qw(overload_info overload_op_info is_overloaded);

sub stash_with_symbol {
    my ($class, $symbol) = @_;

    for my $package (@{mro::get_linear_isa($class)}) {
        my $stash = Package::Stash->new($package);
        my $value_ref = $stash->get_symbol($symbol);
        return ($stash, $value_ref) if $value_ref;
    }
    return;
}

=func is_overloaded

   if (is_overloaded($class_or_object)) { ... }

Returns a boolean indicating whether the given class or object has any
overloading declared.  Note that a bare C<use overload;> with no
actual operators counts as being overloaded.

Equivalent to
L<overload::Overloaded()|overload/overload::Overloaded(arg)>, but
doesn't trigger various bugs associated with it in versions of perl
before 5.16.

=cut

sub is_overloaded {
    my $class = blessed($_[0]) || $_[0];

    # Perl before 5.16 seems to corrupt inherited overload info if
    # there's a lone dereference overload and overload::Overloaded()
    # is called before any object has been blessed into the class.
    return !!("$]" >= 5.016
        ? overload::Overloaded($class)
        : stash_with_symbol($class, '&()')
    );
}

=func overload_op_info

    my $info = overload_op_info($class_or_object, $op);

Returns a hash reference with information about the specified
overloaded operator of the named class or blessed object.

Returns C<undef> if the operator is not overloaded.

See L<overload/Overloadable Operations> for the available operators.

The keys in the returned hash are as follows:

=over

=item class

The name of the class in which the operator overloading was declared.

=item code

A reference to the function implementing the overloaded operator.

=item code_name

The fully qualified name of the function implementing the overloaded operator.

=item method_name (optional)

The name of the method implementing the overloaded operator, if the
overloading was specified as a named method, e.g. C<< use overload $op
=> 'method'; >>.

=item code_class (optional)

The name of the class in which the method specified by C<method_name>
was found.

=item value (optional)

For the special C<fallback> key, the value it was given in C<class>.

=back

=cut

sub overload_op_info {
    my ($class, $op) = @_;
    $class = blessed($class) || $class;

    return undef unless is_overloaded($class);
    my $op_method = $op eq 'fallback' ? "()" : "($op";
    my ($stash, $func) = stash_with_symbol($class, "&$op_method")
        or return undef;
    my $info = {
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
    $info->{code_name} = subname($info->{code})
        if exists $info->{code};

    return $info;
}

=func overload_info

    my $info = overload_info($class_or_object);

Returns a hash reference with information about all the overloaded
operators of specified class name or blessed object.  The keys are the
overloaded operators, as specified in C<%overload::ops> (see
L<overload/Overloadable Operations>), and the values are the hashes
returned by L</overload_op_info>.

=cut

sub overload_info {
    my $class = blessed($_[0]) || $_[0];

    return {} unless is_overloaded($class);

    my (%overloaded);
    for my $op (map split(/\s+/), values %overload::ops) {
        my $info = overload_op_info($class, $op)
            or next;
        $overloaded{$op} = $info
    }
    return \%overloaded;
}

=head1 CAVEATS

Whether the C<fallback> key exists when it has its default value of
C<undef> varies between perl versions: Before 5.18 it's there, in
later versions it's not.

=cut

1;
