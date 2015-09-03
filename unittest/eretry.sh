#!/usr/bin/env bash

FAIL_TIMES=0
fail_then_pass()
{
    $(declare_args failCount)
    einfo "$(lval failCount FAIL_TIMES)"
    (( FAIL_TIMES += 1 ))
    (( ${FAIL_TIMES} <= ${failCount} )) && return 15 || return 0
}

ETEST_eretry_preserve_exit_code()
{
    eretry -r=3 fail_then_pass 3 && die "eretry should abort" || assert_eq 15 $?

    # Ensure fail_then_pass was actually called specified number of times
    assert_eq 3 ${FAIL_TIMES}
}

ETEST_eretry_fail_till_last()
{
    eretry -r=3 fail_then_pass 2
    assert_zero $?

    # Ensure fail_then_pass was actually called specified number of times
    assert_eq 3 ${FAIL_TIMES}
}

ETEST_eretry_exit_124_on_timeout()
{
    eretry -r=1 -t=0.1s sleep infinity && die "eretry should abort" || assert_eq 124 $?
}

ETEST_eretry_warn_every()
{
    EDEBUG=

    output=$(eretry -r=10 -w=2 false 2>&1 || true)
    einfo "$(lval output)"
    assert_eq 5 $(echo "$output" | wc -l)

    output=$(eretry -r=30 -w=3 false 2>&1 || true)
    einfo "$(lval output)"
    assert_eq 10 $(echo "$output" | wc -l)

    output=$(eretry -r=3 -w=1 false 2>&1 || true)
    einfo "$(lval output)"
    assert_eq 3 $(echo "$output" | wc -l)

    output=$(eretry -r=0 -w=1 false 2>&1 || true)
    einfo "$(lval output)"
    assert_eq 1 $(echo "$output" | wc -l)
}

ETEST_eretry_hang()
{
    eretry -t=1s -r=0 sleep infinity && die "eretry should abort" || assert_eq 124 $?
}

block_sigterm_and_sleep_forever()
{
    trap '' SIGTERM
    sleep infinity
}

ETEST_eretry_ignore_signal()
{
    eretry -t=1s -r=1 block_sigterm_and_sleep_forever && die "eretry should abort" || assert_eq 137 $?
}

ETEST_eretry_multiple_commands()
{
    eretry eval "mkdir -p foo; echo -n 'zap' > foo/file"
    [[ -d foo      ]] || die "foo doesn't exist"
    [[ -f foo/file ]] || die "foo/file doesn't exist"
    assert_eq "zap" "$(cat foo/file)"
}

quoting_was_preserved()
{
    [[ $1 == "a b" && $2 == "c" && $3 == "the lazy fox jumped!" ]]
}

ETEST_eretry_preserves_quoted_whitespace()
{
    eretry -r=0 quoting_was_preserved "a b" "c" "the lazy fox jumped!"
}


