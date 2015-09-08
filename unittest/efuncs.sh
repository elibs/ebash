#!/usr/bin/env bash

ETEST_argcheck()
{
    try
    {
        alpha="notempty"
        output=$((argcheck alpha beta 2>&1))
        die "argcheck should have thrown"
    }
    catch
    {
        return 0
    }

    die "argcheck should have thrown"
}

ETEST_edebug_one_and_zero()
{
    EDEBUG=1 edebug_enabled || die "edebug should be enabled"
    EDEBUG=0 edebug_enabled && die "edebug should not be enabled" || true
}

ETEST_edebug_enabled_matcher()
{
    EDEBUG="ETEST_edebug_enabled_matcher" edebug_enabled  || die
    EDEBUG="efuncs"                       edebug_enabled  || die
    EDEBUG="something else entirely"      edebug_disabled || die
    EDEBUG="else and edebug"              edebug_enabled  || die
    EDEBUG=""                             edebug_disabled || die
}

ETEST_edebug_enabled_skips_edebug_in_stack_frame()
{
    output=$(EDEBUG="ETEST_edebug_enabled_skips_edebug_in_stack_frame" edebug "hello" 2>&1)
    [[ ${output} =~ hello ]] || die
}

ETEST_fully_qualify_hostname_ignores_case()
{
    assert_eq 'bdr-jenkins.eng.solidfire.net' $(fully_qualify_hostname bdr-jenkins)
    assert_eq 'bdr-jenkins.eng.solidfire.net' $(fully_qualify_hostname BDR-JENKINS)

    # This host has its name in all caps (BDR-ES56 in DNS)
    assert_eq 'bdr-es56.eng.solidfire.net' $(fully_qualify_hostname bdr-es56)
    assert_eq 'bdr-es56.eng.solidfire.net' $(fully_qualify_hostname BDR-ES56)
}

ETEST_print_value()
{
    VAR=a
    assert_eq '"a"' "$(print_value VAR)"

    VAR="A[b]"
    assert_eq '"A[b]"' "$(print_value VAR)"

    ARRAY=(a b "c d")
    assert_eq '("a" "b" "c d")' "$(print_value ARRAY)"

    declare -A AA
    AA[alpha]="1 2 3"
    AA[beta]="4 5 6"

    assert_eq '([alpha]="1 2 3" [beta]="4 5 6" )' "$(print_value AA)"

    unset V
    assert_eq '""' "$(print_value V)"

    assert_eq '""' "$(print_value /usr/local/share)"
}

ETEST_detect_var_types()
{
    A=a
    ARRAY=(1 2 3)

    declare -A AA
    AA[alpha]=1
    AA[beta]=2

    pack_set P A=1

    is_array A && die
    is_associative_array A && die
    is_pack A && die

    is_array               ARRAY || die
    is_associative_array   ARRAY && die
    is_pack                ARRAY && dei

    is_array               AA && die
    is_associative_array   AA || die
    is_pack                AA && die

    is_array               +P && die
    is_associative_array   +P && die
    is_pack                +P || die
}

# Ensure local variable assignments don't mask errors. Specifically things of this form:
# 'local x=$(false)' need to still trigger fatal error handling.
ETEST_local_variables_masking_errors()
{
    try
    {
        local foo=$(false)
        die "local variable assignment should have thrown"
    }
    catch
    {
        return 0
    }

    die "try block should have thrown"
}
