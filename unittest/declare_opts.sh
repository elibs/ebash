#!/usr/bin/env bash

ETEST_declare_opts()
{
    set -- --file some_file --longer --long --whitespace "arg with whitespace" -shktlc blue -m -n arg1 arg2 arg3
    $(declare_opts                                                          \
        ":file f"                       "Which file should be processed."   \
        ":color c=yellow"               "Color to be used."                 \
        "?long l longer s h k t m n"    "option with lots of variants"      \
        ":whitespace w"                 "option expecting to receive something containing whitespace")

    assert_eq "blue" "$(dopt_get color)"
    assert_eq "some_file" "$(dopt_get file)"

    assert_eq "arg1" "$1"
    assert_eq "arg2" "$2"
    assert_eq "arg3" "$3"
}

ETEST_declare_opts_boolean()
{
    set -- -a -b -c d e f
    $(declare_opts \
        "a" "" \
        "b" "" \
        "c" "" \
        "d" "" \
        "e" "" \
        "f" "")

    assert_eq 1 "$(dopt_get a)"
    assert_true dopt_true a
    assert_eq 1 "$(dopt_get b)"
    assert_true dopt_true b
    assert_eq 1 "$(dopt_get c)"
    assert_true dopt_true c

    assert_eq 0 "$(dopt_get d)"
    assert_false dopt_true d
    assert_eq 0 "$(dopt_get e)"
    assert_false dopt_true e
    assert_eq 0 "$(dopt_get f)"
    assert_false dopt_true f
}

ETEST_declare_opts_boolean_multi()
{
    set -- --another -va --verbose -vv -s --else
    $(declare_opts          \
        "verbose v"     ""  \
        "another a"     ""  \
        "something s"   ""  \
        "else e"        "")

    assert_eq 1 "$(dopt_get verbose)"
    assert_eq 1 "$(dopt_get another)"
    assert_eq 1 "$(dopt_get something)"
    assert_eq 1 "$(dopt_get else)"

    assert_true dopt_get verbose
    assert_true dopt_get another
    assert_true dopt_get something
    assert_true dopt_get else
}

ETEST_declare_opts_short()
{
    set -- -nf a_file -c salmon -d=door
    $(declare_opts                  \
        ":file f"   "the file"      \
        "numeric n" "a number"      \
        ":color c"  "the color"     \
        ":door d"   "another argument")


    assert_eq "a_file" $(dopt_get file)
    assert_eq "salmon" $(dopt_get color)
    assert_eq "door"   $(dopt_get door)
}

ETEST_declare_opts_long()
{
    set -- --foo alpha --bar 10 --baz=30
    $(declare_opts \
        ":foo" "" \
        ":bar" "" \
        ":baz" "")

    assert_eq "alpha" $(dopt_get foo)
    assert_eq "10"    $(dopt_get bar)
    assert_eq "30"    $(dopt_get baz)
}

ETEST_declare_opts_required_arg()
{
    set -- -a
    try
    {
        $(declare_opts ":a" "")

        die -r=243 "Should have failed parsing options."
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_shorts_crammed_together_with_arg()
{
    set -- -abc optarg arg
    $(declare_opts \
        "a" "" \
        "b" "" \
        ":c" "")

    assert_eq 1 $(dopt_get a)
    assert_eq 1 $(dopt_get b)
    assert_eq optarg $(dopt_get c)

    assert_eq "arg" "$1"
}

ETEST_declare_opts_shorts_crammed_together_required_arg()
{
    set -- -abc
    try
    {
        $(declare_opts \
            "a" "" \
            "b" "" \
            ":c" "") 

        die -r=243 "Should have failed when parsing options but did not."
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_crazy_option_args()
{
    alpha="how about	whitespace?"
    beta="[]"
    gamma="*"
    kappa="\$1"

    set -- --alpha "${alpha}" --beta "${beta}" --gamma "${gamma}" --kappa "${kappa}"
    $(declare_opts ":alpha" "" ":beta" "" ":gamma" "" ":kappa" "")

    assert_eq "${alpha}" "$(dopt_get alpha)"
    assert_eq "${gamma}" "$(dopt_get gamma)"
    assert_eq "${beta}"  "$(dopt_get beta)"
    assert_eq "${kappa}" "$(dopt_get kappa)"
}

ETEST_declare_opts_arg_hyphen()
{
    set -- --foo - arg1
    $(declare_opts ":foo" "")

    [[ "$(dopt_get foo)" == "-" ]] || die "Foo argument was wrong"

    assert_eq "arg1" "$1"
}

ETEST_declare_opts_unexpected_short()
{
    set -- -a
    try
    {
        $(declare_opts "b" "")

        die -r=243 "Failed to blow up on unexpected option"
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_unexpected_long()
{
    set -- --foo
    try
    {
        $(declare_opts "bar" "")

        die -r=243 "Failed to blow up on unexpected option"
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_unexpected_equal_long()
{
    set -- --foo=1
    try
    {
        $(declare_opts "foo" "")

        die -r=243 "Failed to blow up on unexpected argument to option"
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_unexpected_equal_short()
{
    set -- -f=1
    try
    {
        $(declare_opts "foo f" "")

        die -r=243 "Failed to blow up on unexpected argument to option"
    }
    catch
    {
        assert_ne 243 $?
    }
}

ETEST_declare_opts_default()
{
    set --
    $(declare_opts                      \
        "alpha a=5" ""                  \
        ":beta b=3" ""                  \
        ":white w=with whitespace" "")

    assert_eq 5 "$(dopt_get alpha)"
    assert_eq 3 "$(dopt_get beta)"
    assert_eq "with whitespace" "$(dopt_get white)"
}

ETEST_declare_opts_boolean_defaults()
{
    set -- -a -b
    $(declare_opts  \
        "a=0" ""    \
        "b=1" ""    \
        "c=0" ""    \
        "d=1" "")

    assert_eq 1  "$(dopt_get a)"
    assert_true  dopt_true a
    assert_false dopt_false a

    assert_eq 1  "$(dopt_get b)"
    assert_true  dopt_true b
    assert_false dopt_false b

    assert_eq 0  "$(dopt_get c)"
    assert_false dopt_true c
    assert_true  dopt_false c

    assert_eq 1  "$(dopt_get d)"
    assert_true  dopt_true d
    assert_false dopt_false a
}

ETEST_declare_opts_get_fails_on_undeclared_option()
{
    set -- -a
    $(declare_opts "a" "")

    assert_false dopt_get b
    assert_false dopt_get alpha
    assert_false dopt_true b
    assert_false dopt_true alpha

    assert_true dopt_get a
}

ETEST_declare_opts_recursive()
{

    foo()
    {
        $(declare_opts \
            ":as a" "" \
            ":be b" "" \
            ":c"    "")

        bar --as 6 -b=5 -c 4

        assert_eq 3 $(dopt_get as)
        assert_eq 2 $(dopt_get be)
        assert_eq 1 $(dopt_get c)
    }

    bar()
    {
        $(declare_opts \
            ":as a" "" \
            ":be b" "" \
            ":c"    "")

        assert_eq 6 $(dopt_get as)
        assert_eq 5 $(dopt_get be)
        assert_eq 4 $(dopt_get c)

    }

    foo  --as 3 -b=2 -c 1
}

# NOTE: Please ignore for the moment.  Declare_opts is still a work in progress
# and isn't integrated into anything for "real" use yet.
#ETEST_declare_opts_refuses_option_starting_with_no()
#{
#    try
#    {
#        $(declare_opts "no-option" "")
#
#        die -r=243 "Should have failed before reaching this point."
#    }
#    catch
#    {
#        assert_ne 243 $?
#    }
#}

# TODO --no-option
# TODO replace old opt_get functions with new ones
# TODO test on 12.04
