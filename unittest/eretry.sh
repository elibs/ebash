#!/usr/bin/env bash

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

ETEST_eretry_ignore_signals_off()
{
    rm -f child.pid
    rm -f child.ticks
    echo -n "0" > child.ticks

    eretry -t=infinity -r=2 do_sleep &
    local retry_pid=$!
   
    # Wait for pid to be there
    einfo "Waiting for child.pid"
    until [[ -s child.pid ]]; do
        sleep 1
    done

    local sleep_pid=$(cat child.pid)
    einfo "$(lval retry_pid sleep_pid)"

    # Send SIGTERM to process inside eretry
    ekilltree -s=SIGTERM ${sleep_pid}
  
    # Wait for sleep process to abort and retry process to abort
    eprogress "Waiting for eretry process to stop"
    wait ${retry_pid} || true
    eprogress_kill

    assert process_not_running ${sleep_pid}
    assert process_not_running ${retry_pid}

    # Should have only run 1 time
    assert_eq 1 $(cat child.ticks)
}   

ETEST_eretry_ignore_signals_on()
{
    rm -f child.pid
    rm -f child.ticks
    echo -n "0" > child.ticks

    local respawns=2
    eretry -t=infinity -r=${respawns} -i do_sleep &
    local retry_pid=$!
   
    local tries
    for (( tries=0; tries<${respawns}; tries++ )); do

        # Wait for pid to be there
        einfo "Waiting for child.pid"
        until [[ -s child.pid ]]; do
            sleep 1
        done

        local sleep_pid=$(cat child.pid)
        einfo "$(lval retry_pid sleep_pid)"

        # Send SIGTERM to process inside eretry
        ekilltree -s=SIGTERM ${sleep_pid}

        # Sleep between intervals to give process a chance to respawn
        sleep 1
    done

    # Wait for sleep process to abort and retry process to abort
    eprogress "Waiting for eretry process to stop"
    wait ${retry_pid} || true
    eprogress_kill

    assert process_not_running ${sleep_pid}
    assert process_not_running ${retry_pid}

    # Should have only run 1 time
    assert_eq ${respawns} $(cat child.ticks)
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

    local output=$(eretry -r=2 -t=2s callback)
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

