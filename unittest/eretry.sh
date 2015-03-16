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
    EFUNCS_FATAL=0
    RETRIES=3 eretry fail_then_pass 3 &>$(edebug_out)
    expect_eq 15 $?
}

ETEST_eretry_fail_till_last()
{
    RETRIES=3 eretry fail_then_pass 2
    expect_zero $?
}

ETEST_eretry_exit_124_on_timeout()
{
    EFUNCS_FATAL=0
    RETRIES=0 TIMEOUT=0.1s eretry sleep 3 &>$(edebug_out)
    expect_eq 124 $?
}

ETEST_eretry_warn_every()
{
    EFUNCS_FATAL=0

    output=$(RETRIES=10 WARN_EVERY=2 eretry false 2>&1)
    expect_eq 5 $(echo "$output" | wc -l)

    output=$(RETRIES=30 WARN_EVERY=3 eretry false 2>&1)
    expect_eq 10 $(echo "$output" | wc -l)

    output=$(RETRIES=3 WARN_EVERY=1 eretry false 2>&1)
    expect_eq 3 $(echo "$output" | wc -l)

    output=$(RETRIES=0 WARN_EVERY=1 eretry false 2>&1)
    expect_eq 1 $(echo "$output" | wc -l)
}
