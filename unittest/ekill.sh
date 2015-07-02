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
    sleep infinity& pids+=( $! )
    yes >/dev/null& pids+=( $! )
    bash -c 'sleep 1000' & pids+=( $! )
    bash -c 'sleep 4000' & pids+=( $! )

    ekilltree $$

    for pid in ${pids[@]}; do
        wait $pid || true
        ! process_running ${pid} || die "${pid} failed to exit"
    done
}
