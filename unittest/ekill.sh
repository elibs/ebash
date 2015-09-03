#!/usr/bin/env bash

ETEST_ekill()
{
    # Start a simple process and ensure we can kill it
    yes >/dev/null &
    local pid=$!
    process_running ${pid}   || die "${pid} should be running"

    ekill ${pid}
    wait ${pid} || true
    ! process_running ${pid} || die "${pid} should have been killed!"
}

ETEST_ekill_multiple()
{
    local pids=()
    yes >/dev/null &
    pids+=( $! )

    local idx
    for (( idx=0; idx<10; ++idx )); do
        sleep infinity &
        pids+=( $! )
    done

    einfo "Killing all $(lval pids)"
    ekill ${pids[@]}

    for pid in ${pids[@]}; do
        wait $pid || true
        ! process_running ${pid} || die "${pid} failed to exit"
    done
}

ETEST_ekilltree()
{
    local pids=()

    # Create a bunch of background processes
    (
        sleep infinity& pids+=( $! )
        yes >/dev/null& pids+=( $! )
        bash -c 'sleep 1000' & pids+=( $! )
    ) & pids+=( $! )
    bash -c 'sleep 4000' & pids+=( $! )

    ekilltree ${pids[@]}

    for pid in ${pids[@]}; do
        wait $pid || true
        ! process_running ${pid} || die "${pid} failed to exit"
    done
}

ETEST_die()
{
    try
    {
        # Create a bunch of background processes
        sleep infinity& echo "$!" >> pids
        yes >/dev/null& echo "$!" >> pids
        bash -c 'sleep 1000' & echo "$!" >> pids
        bash -c 'sleep 4000' & echo "$!" >> pids

        die
    }
    catch
    {
        true
    }

    for pid in $(cat pids); do
        eretry -t=2s process_not_running ${pid} || die "${pid} failed to get killed by die"
    done
}
