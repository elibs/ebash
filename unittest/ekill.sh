ETEST_ekill()
{
    # Start a simple process and ensure we can kill it
    yes >/dev/null &
    local pid=$!

    ekill ${pid}
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

do_stuff()
{
    sleep infinity &
    yes >/dev/null &
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
