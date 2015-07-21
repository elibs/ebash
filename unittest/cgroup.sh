
$(esource $(dirname $0)/cgroup.sh)

ETEST_cgroup_pids_recursive()
{
    (
        cgroup_add cgroup_pids_recursive ${BASHPID}
        PARENT_PID=${BASHPID}
        (
            cgroup_add cgroup_pids_recursive/subgroup ${BASHPID}

            local allPids=($(cgroup_pids cgroup_pids_recursive))

            einfo BASHPID=${BASHPID} $(lval allPids PARENT_PID)

            assert_true array_contains allPids ${BASHPID}
            assert_true array_contains allPids ${PARENT_PID}
        )
    )
}

ETEST_cgroup_add_multiple_pids_at_once()
{
    local PIDS=()
    sleep 100 &
    PIDS+=($!)
    sleep 100 &
    PIDS+=($!)

    cgroup_add cgroup_add_multiple_pids_at_once "${PIDS[@]}"

    local foundPids=($(cgroup_pids cgroup_add_multiple_pids_at_once))
    for pid in "${PIDS[@]}" ; do
        assert_true array_contains foundPids $pid
    done
}

ETEST_cgroup_add_ignores_empties()
{
    # Adding an empty string to the tasks file in the cgroup filesystem would
    # typically blow up.  Cgroup_add intentionally skips empty strings to make
    # life a bit easier.
    cgroup_add cgroup_add_ignores_empties "" ${BASHPID} ""
}
