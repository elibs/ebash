#!/usr/bin/env bash

ETEST_elock()
{
    touch ${FUNCNAME}

    elock ${FUNCNAME}
    eunlock ${FUNCNAME}
}

ETEST_unlock_before_lock()
{
    touch ${FUNCNAME}
    assert_false eunlock ${FUNCNAME}
}

ETEST_elock_recursive()
{
    touch ${FUNCNAME}

    elock ${FUNCNAME}
    assert_false elock ${FUNCNAME}
}

ETEST_elock_auto_unlock()
{
    touch ${FUNCNAME}

    (
        etimeout -t=1s elock ${FUNCNAME}
    )

    (
        etimeout -t=1s elock ${FUNCNAME}
    )
}

ETEST_elock_concurrent()
{
    touch ${FUNCNAME}

    (
        elock ${FUNCNAME}

        local idx
        for idx in {1..5}; do
            echo -n "$idx" >>${FUNCNAME}
        done

        sleep 5

        for idx in {6..10}; do
            echo -n "$idx" >>${FUNCNAME}
        done
    ) &

    (
        # Wait for lock
        eretry -T=30s elock ${FUNCNAME}
    
        local idx
        for idx in {a..e}; do
            echo -n "$idx" >>${FUNCNAME}
        done
    ) &

    # Wait for backgrounded process to complete
    wait

    # Show file
    etestmsg "Showing file"
    cat ${FUNCNAME}
    echo ""

    # File should match expected results
    assert_eq "12345678910abcde" "$(cat ${FUNCNAME})"
}
