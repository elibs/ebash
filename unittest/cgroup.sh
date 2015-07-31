
$(esource $(dirname $0)/cgroup.sh)


################################################################################
################################################################################
# NOTE: Tests currently disabled because the gentoo machines that run bashutils
# unit tests automatically do not have proper cgroups support compiled into
# their kernels.
################################################################################
################################################################################

#ETEST_cgroup_pids_recursive()
#{
#    (
#        cgroup_add cgroup_pids_recursive ${BASHPID}
#        PARENT_PID=${BASHPID}
#        (
#            cgroup_add cgroup_pids_recursive/subgroup ${BASHPID}
#
#            local allPids=($(cgroup_pids cgroup_pids_recursive))
#
#            einfo BASHPID=${BASHPID} $(lval allPids PARENT_PID)
#
#            assert_true array_contains allPids ${BASHPID}
#            assert_true array_contains allPids ${PARENT_PID}
#        )
#    )
#}
#
#ETEST_cgroup_add_multiple_pids_at_once()
#{
#    local PIDS=()
#    sleep 100 &
#    PIDS+=($!)
#    sleep 100 &
#    PIDS+=($!)
#
#    cgroup_add cgroup_add_multiple_pids_at_once "${PIDS[@]}"
#
#    local foundPids=($(cgroup_pids cgroup_add_multiple_pids_at_once))
#    for pid in "${PIDS[@]}" ; do
#        assert_true array_contains foundPids ${pid}
#    done
#
#    cgroup_kill cgroup_add_multiple_pids_at_once
#}
#
#ETEST_cgroup_add_ignores_empties()
#{
#    # Adding an empty string to the tasks file in the cgroup filesystem would
#    # typically blow up.  Cgroup_add intentionally skips empty strings to make
#    # life a bit easier.
#    cgroup_add cgroup_add_ignores_empties "" ${BASHPID} ""
#}
#
#ETEST_cgroup_pids_checks_all_subsystems()
#{
#    local CGROUP=cgroup_pids_checks_all_subsystems
#
#    # Create a process in the cgroup
#    sleep infinity&
#    local pid=$!
#    cgroup_add ${CGROUP} ${pid}
#
#    # Remove it from the cgroup in a single subsystem (arbitrarily #1)
#    echo ${pid} > /sys/fs/cgroup/${CGROUP_SUBSYSTEMS[1]}/tasks
#
#    # Make sure it still shows up in the list of pids
#    local foundPids=($(cgroup_pids ${CGROUP}))
#    einfo "$(lval pid foundPids)"
#    assert_true array_contains foundPids ${pid}
#
#}

