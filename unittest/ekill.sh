ETEST_ekill()
{
    # Start a simple process and ensure we can kill it
    yes >/dev/null &
    local pid=$!
    process_running ${pid}     || die "${pid} should be running"

    ekill ${pid}
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
}

ETEST_ekilltree()
{
    # Create a bunch of background processes
    sleep infinity&
    yes >/dev/null&
    bash -c 'sleep 1000' &
    bash -c 'sleep 4000' &

    local pid=$$
    einfo "$(lval pid)"
    ekilltree ${pid}
}
