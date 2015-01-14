
ETEST_argcheck()
{
    EFUNCS_FATAL=0

    alpha="notempty"
    output=$(
        ( 
            argcheck alpha beta 2>&1
            expect_true false
        )
    )

    expect_not_zero $?
    expect_true  'echo "$output" | grep -q beta'
    expect_false 'echo "$output" | grep -q alpha'
}

ETEST_edebug_one_and_zero()
{
    EDEBUG=1 edebug_enabled
    expect_zero $?

    EDEBUG=0 edebug_enabled
    expect_not_zero $?
}

ETEST_edebug_enabled_matcher()
{
    EDEBUG="ETEST_edebug_enabled_matcher" edebug_enabled
    expect_zero $?

    EDEBUG="efuncs"                       edebug_enabled
    expect_zero $?

    EDEBUG="something else entirely"      edebug_enabled
    expect_not_zero $?

    EDEBUG="else and edebug"              edebug_enabled
    expect_zero $?

    EDEBUG=""                             edebug_enabled
    expect_not_zero $?
}

ETEST_edebug_enabled_skips_edebug_in_stack_frame()
{
    output=$(EDEBUG="ETEST_edebug_enabled_skips_edebug_in_stack_frame" edebug "hello" 2>&1)
    expect_true '[[ ${output} =~ hello ]]'
}

ETEST_fully_qualify_hostname_ignores_case()
{
    expect_eq 'bdr-jenkins.eng.solidfire.net' $(fully_qualify_hostname bdr-jenkins)
    expect_eq 'bdr-jenkins.eng.solidfire.net' $(fully_qualify_hostname BDR-JENKINS)

    # This host has its name in all caps (BDR-ES56 in DNS)
    expect_eq 'bdr-es56.eng.solidfire.net' $(fully_qualify_hostname bdr-es56)
    expect_eq 'bdr-es56.eng.solidfire.net' $(fully_qualify_hostname BDR-ES56)
}
