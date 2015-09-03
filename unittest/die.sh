#!/usr/bin/env bash

ETEST_die_subprocesses()
{
    local pid1_file=$(mktemp die_subprocess-XXXXXX.pid)
    local pid2_file=$(mktemp die_subprocess-XXXXXX.pid)

    einfo "Starting two subprocesses"
    try
    {
        yes &>/dev/null &
        echo "$!" > ${pid1_file}
        einfos "pid1=$(cat ${pid1_file})"

        yes &>/dev/null &
        echo "$!" > ${pid2_file}
        einfos "pid2=$(cat ${pid1_file})"

        die
    }
    catch
    {
        einfo "Called die inside try/catch block"
    }

    # Verify processes were both killed
    local pid1=$(cat ${pid1_file})
    local pid2=$(cat ${pid2_file})

    einfo "Ensuring processes were killed"
    kill -0 ${pid1} && die "Process should have been killed $(lval pid1)"
    kill -0 ${pid2} && die "Process should have been killed $(lval pid2)"

    return 0
}
