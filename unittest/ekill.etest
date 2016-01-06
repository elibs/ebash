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
    > pids
    yes >/dev/null & echo "$!" >> pids

    local idx
    for (( idx=0; idx<10; ++idx )); do
        sleep infinity &
        echo "$!" >> pids
    done

    local pids=( $(cat pids) )
    einfo "Killing all $(lval pids)"
    ekill ${pids[@]}

    for pid in ${pids[@]}; do
        einfo "Waiting for $(lval pid pids SECONDS)"
        wait $pid || true
        ! process_running ${pid} || die "${pid} failed to exit"
    done
}

ETEST_ekilltree()
{
    > pids

    # Create a bunch of background processes
    (
        sleep infinity&        echo "$!" >> pids
        yes >/dev/null&        echo "$!" >> pids
        bash -c 'sleep 1000'&  echo "$!" >> pids

        # Keep the entire subshell from exiting and having above processes get
        # reparented to init.
        sleep infinity || true
    ) &

    local main_pid=$!
    echo "${main_pid}" >> pids

    local pids=( $(cat pids) )
    einfo "Killing $(lval main_pid) -- Expecting death from $(lval pids)"
    ekilltree ${main_pid}

    for pid in ${pids[@]}; do
        einfo "Waiting for $(lval pid pids SECONDS)"
        wait $pid || true
        assert_false process_running ${pid}
    done
}

ETEST_ekilltree_excludes_self()
{
    > pid

    try
    {
        sleep infinity&
        echo $! >> pid

        ekilltree -s=TERM ${BASHPID}
        ekilltree -s=KILL ${BASHPID}
    }
    catch
    {
        assert [[ $? -eq 0 ]]
    }

    assert_false process_running $(cat pid)
}

ETEST_ekilltree_exclude_abritrary()
{
    > safe_pid
    > kill_pid

    try
    {
        sleep infinity&
        echo $! >> safe_pid

        sleep infinity&
        echo $! >> kill_pid

        ekilltree -x="$(cat safe_pid)" -s=TERM ${BASHPID}
    }
    catch
    {
        assert [[ $? -eq 0 ]]
    }

    assert process_running $(cat safe_pid)
    eretry -T=2s process_not_running $(cat kill_pid)

    ekill -s=KILL $(cat safe_pid)
}
