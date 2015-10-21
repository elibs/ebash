#!/usr/bin/env bash

ETEST_eretry_empty_command()
{
    eretry ""
}

ETEST_etimeout_empty_command()
{
    etimeout -t=1 ""
}

FAIL_TIMES=0
fail_then_pass()
{
    $(declare_args failCount tmpfile)

    # Initialize counter to 0
    [[ -f ${tmpfile} ]] || echo "0" > ${tmpfile}

    # Read counter from file and increment it
    FAIL_TIMES=$(cat ${tmpfile})
    (( FAIL_TIMES += 1 ))
    echo "${FAIL_TIMES}" > ${tmpfile}

    einfo "$(lval failCount FAIL_TIMES)"
    (( ${FAIL_TIMES} <= ${failCount} )) && return 15 || return 0
}

ETEST_eretry_preserve_exit_code()
{
    $(tryrc eretry -r=3 fail_then_pass 3 tmpfile)
    [[ ${rc} -eq 0 ]] && die "eretry should abort" || assert_eq 15 ${rc} "exit code"

    # Ensure fail_then_pass was actually called specified number of times
    assert_eq 3 $(cat tmpfile) "number of times"
}

ETEST_eretry_fail_till_last()
{
    eretry -r=3 fail_then_pass 2 tmpfile
    assert_zero $?

    # Ensure fail_then_pass was actually called specified number of times
    assert_eq 3 $(cat tmpfile) "number of attempts"
}

ETEST_eretry_exit_124_on_timeout()
{
    eretry -r=1 -t=0.1s sleep infinity && die "eretry should abort" || assert_eq 124 $?
}

# Disabled b/c this test just takes way too long and provides almost no value.
DISABLED_ETEST_eretry_warn_every()
{
    EDEBUG=

    callback()
    {
        sleep .1
        false
    }

    etestmsg "Calling callback 50 times warn every 1 second -- expecting >= 5"
    $(EDEBUG="" tryrc -o=stdout -e=stderr eretry -r=50 -w=1 callback)
    einfo "$(lval stderr stdout)"
    assert [[ "$(echo -n "$stderr" | wc -l)" -ge 5 ]]

    etestmsg "Calling callback 80 times warn every 3 seconds -- expecting >= 3"
    $(EDEBUG="" tryrc -o=stdout -e=stderr eretry -r=80 -w=3 callback)
    einfo "$(lval stderr)"
    assert [[ "$(echo -n "$stderr" | wc -l)" -ge 3 ]]

    etestmsg "Calling callback 30 times warn every 1 second -- expecting >= 3"
    $(EDEBUG="" tryrc -o=stdout -e=stderr eretry -r=30 -w=1 callback 2>&1)
    einfo "$(lval stderr)"
    assert [[ "$(echo -n "$stderr" | wc -l)" -ge 3 ]]

    etestmsg "Calling callback 0 times warn every 1 second -- expecting == 0"
    $(EDEBUG="" tryrc -o=stdout -e=stderr eretry -r=0 -w=1 callback)
    einfo "$(lval stderr)"
    assert [[ "$(echo -n "$stderr" | wc -l)" -eq 0 ]]
}

ETEST_eretry_hang()
{
    $(tryrc eretry -t=1s -r=1 sleep infinity)
    assert_eq 124 ${rc}
}

ETEST_eretry_hang_block_sigterm()
{
    block_sigterm_and_sleep_forever()
    {
        die_on_abort
        trap '' SIGTERM
        sleep infinity
    }

    $(tryrc eretry -t=1s -r=1 block_sigterm_and_sleep_forever)
    einfo "eretry completed with $(lval rc)"
    assert_eq 124 $rc
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

ETEST_eretry_alternate_exit_code()
{
    $(tryrc eretry -e=15 fail_then_pass 10 tmpfile)
    assert_eq 15 ${rc} "return code"
    assert_eq 1 "$(cat tmpfile)" "number of attempts"
}

do_sleep()
{
    local ticks=$(cat child.ticks || true)
    (( ticks += 1 ))
    
    echo ${BASHPID}  > child.pid
    echo ${ticks}    > child.ticks
    sleep infinity
}

ETEST_eretry_partial_output()
{
    echo -n "0" > calls.txt

    callback()
    {
        # On first call return partial json output and fail
        local calls=$(cat calls.txt)
        einfo "Callback called: $(lval calls)"
        echo "$(( calls + 1 ))" > calls.txt

        if [[ ${calls} -eq 0 ]]; then
            echo -n '{"key":"va'
            return 1
        fi

        echo -n '{"key":"value"}'
        return 0
    }

    local output=$(eretry -r=2 callback)
    einfo "$(lval output)"
    echo "${output}" | jq .
    assert_eq '{"key":"value"}' "${output}"
}

ETEST_eretry_partial_output_timeout()
{
    echo -n "0" > calls.txt

    callback()
    {
        # On first call return partial json output and fail
        local calls=$(cat calls.txt)
        einfo "Callback called: $(lval calls)"
        echo "$(( calls + 1 ))" > calls.txt

        if [[ ${calls} -eq 0 ]]; then
            echo -n '{"key":"va'
            sleep infinity
        fi

        echo -n '{"key":"value"}'
        return 0
    }

    local output=$(eretry -r=2 -t=.5s callback)
    einfo "$(lval output)"
    echo "${output}" | jq .
    assert_eq '{"key":"value"}' "${output}"
}

ETEST_eretry_total_timeout()
{
    $(tryrc eretry -T=1 sleep infinity)
    assert_eq 124 ${rc}
}

ETEST_eretry_default_count()
{
    echo -n "0" > calls.txt

    callback()
    {
        local calls=$(cat calls.txt)
        einfo "Callback called: $(lval calls)"
        echo "$(( calls + 1 ))" > calls.txt

        false
    }

    $(tryrc eretry callback)

    assert_eq "5" "$(cat calls.txt)"
}

ETEST_eretry_subshell_die_should_retry()
{
    rm -f file

    foo()
    {
        (
            if ! [[ -e file ]] ; then
                touch file
                die -r=50 "Die from the subshell, but eretry should continue"
            else
                echo "RETRIED" > file
                einfo "Retried successfully"
            fi
        )
    }

    eretry -r=2 foo

    assert_eq "RETRIED" "$(cat file)"
}

ETEST_eretry_false()
{
    $(tryrc eretry -r=2 false)
    assert [[ ${rc} -ne 0 ]]
}

ETEST_eretry_true()
{
    $(tryrc eretry -r=2 true)
    assert [[ ${rc} -eq 0 ]]
}
