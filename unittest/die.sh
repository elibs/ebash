#!/usr/bin/env bash

ETEST_die_subprocesses()
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
