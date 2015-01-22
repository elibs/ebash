FAIL_TIMES=0
fail_then_pass()
{
    eval "$(declare_args failCount)"
    edebug "$(lval failCount FAIL_TIMES)"
    (( FAIL_TIMES += 1 ))
    (( ${FAIL_TIMES} <= ${failCount} )) && return 15 || return 0
}

ETEST_eretry_preserve_exit_code()
{
    OUTPUT=/dev/null
    edebug_enabled && OUTPUT=/dev/stderr

    EFUNCS_FATAL=0
    RETRIES=3 eretry fail_then_pass 3 &>${OUTPUT}
    expect_eq 15 $?
}

ETEST_eretry_fail_till_last()
{
    RETRIES=3 eretry fail_then_pass 2
    expect_zero $?
}

ETEST_eretry_exit_124_on_timeout()
{
    OUTPUT=/dev/null
    edebug_enabled && OUTPUT=/dev/stderr

    EFUNCS_FATAL=0
    RETRIES=0 TIMEOUT=0.1s eretry sleep 3 &>${OUTPUT}
    expect_eq 124 $?
}
