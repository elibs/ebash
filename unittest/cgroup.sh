
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
