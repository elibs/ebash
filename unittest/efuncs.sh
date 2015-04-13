
ETEST_argcheck()
{
    EFUNCS_FATAL=0

    alpha="notempty"
    output=$(
        ( 
            argcheck alpha beta 2>&1
            assert_true false
        )
    )

    assert_not_zero $?
    echo "$output" | grep -q beta  || die
    echo "$output" | grep -q alpha && die
}

ETEST_edebug_one_and_zero()
{
    EDEBUG=1 edebug_enabled
    assert_zero $?

    EDEBUG=0 edebug_enabled
    assert_not_zero $?
}

ETEST_edebug_enabled_matcher()
{
    EDEBUG="ETEST_edebug_enabled_matcher" edebug_enabled
    assert_zero $?

    EDEBUG="efuncs"                       edebug_enabled
    assert_zero $?

    EDEBUG="something else entirely"      edebug_enabled
    assert_not_zero $?

    EDEBUG="else and edebug"              edebug_enabled
    assert_zero $?

    EDEBUG=""                             edebug_enabled
    assert_not_zero $?
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
