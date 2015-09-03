#!/usr/bin/env bash

$(esource $(dirname $0)/cgroup.sh)

################################################################################
################################################################################
# NOTE: Tests currently disabled because the gentoo machines that run bashutils
# unit tests automatically do not have proper cgroups support compiled into
# their kernels.
################################################################################
################################################################################

ETEST_cgroup_pids_recursive()
{
    (
        cgroup_move cgroup_pids_recursive ${BASHPID}
        PARENT_PID=${BASHPID}
        (
            cgroup_move cgroup_pids_recursive/subgroup ${BASHPID}

            local allPids
            allPids=($(cgroup_pids cgroup_pids_recursive))

            einfo BASHPID=${BASHPID} $(lval allPids PARENT_PID)

            assert_true array_contains allPids ${BASHPID}
            assert_true array_contains allPids ${PARENT_PID}
        )
    )
}

ETEST_cgroup_move_multiple_pids_at_once()
{
    local PIDS=()
    sleep infinity &
    PIDS+=($!)
    sleep infinity &
    PIDS+=($!)

    einfo "Started sleep processes $(lval PIDS)"
    cgroup_move cgroup_move_multiple_pids_at_once "${PIDS[@]}"

    local foundPids
    foundPids=($(cgroup_pids cgroup_move_multiple_pids_at_once))
    for pid in "${PIDS[@]}" ; do
        assert_true array_contains foundPids ${pid}
    done


    cgroup_kill cgroup_move_multiple_pids_at_once
}

ETEST_cgroup_pids_except()
{
    CGROUP=cgroup_pids_except
    (
        cgroup_move ${CGROUP} ${BASHPID}

        local found_pids pid=${BASHPID}
        array_init found_pids "$(cgroup_pids -x="${pid}" ${CGROUP})"
        ewarn "${pid} found: $(lval found_pids)"
        assert_false array_contains found_pids "${pid}"
    )
}

ETEST_cgroup_move_ignores_empties()
{
    # Adding an empty string to the tasks file in the cgroup filesystem would
    # typically blow up.  cgroup_move intentionally skips empty strings to make
    # life a bit easier.
    cgroup_move cgroup_move_ignores_empties "" ${BASHPID} ""
}

ETEST_cgroup_pids_checks_all_subsystems()
{
    local CGROUP=cgroup_pids_checks_all_subsystems

    # Create a process in the cgroup
    sleep infinity&
    local pid=$!
    cgroup_move ${CGROUP} ${pid}

    einfo "Created a sleep process $(lval pid)"

    # Remove it from the cgroup in a single subsystem (arbitrarily #1)
    echo ${pid} > /sys/fs/cgroup/${CGROUP_SUBSYSTEMS[1]}/tasks

    # Make sure it still shows up in the list of pids
    foundPids=($( cgroup_pids ${CGROUP}))
    einfo "$(lval pid foundPids)"
    einfo "$(ps -hp $pid)"

    assert_true array_contains foundPids ${pid}

    cgroup_kill ${CGROUP}

}

ETEST_cgroup_kill_excepts_current_process()
{
    local CGROUP=cgroup_kill_excepts_current_process

    #einfo "Waiting for stale processes"
    #cgroup_kill_and_wait ${CGROUP}
    #einfo "Done waiting"

    (
        # NOTE: You must add ${BASHPID}, not $$ here because we only want the
        # subshell inside this cgroup

        cgroup_move ${CGROUP} ${BASHPID}
        einfo "Joined cgroup $(lval CGROUP) \$\$=$$ \$BASHPID=${BASHPID} pids=$(cgroup_pids ${CGROUP})"
        cgroup_kill_and_wait -x="${BASHPID} $$" ${CGROUP}

        einfo "Subshell still exists after cgroup_kill_and_wait"
    )

    [[ $? -eq 0 ]] || die "Subshell should not have been killed by cgroup_kill, but it was."
}

ETEST_cgroup_functions_like_empty_cgroups()
{
    local CGROUP=cgroup_functions_like_empty_cgroups
    cgroup_create ${CGROUP}

    local empty
    empty=$(cgroup_pids ${CGROUP})
    [[ -z ${empty} ]]

    cgroup_kill ${CGROUP}
    cgroup_kill_and_wait ${CGROUP}
}

ETEST_cgroup_functions_blow_up_on_nonexistent_cgroups()
{
    local CGROUP=cgroup_functions_blow_up_on_nonexistent_cgroups

    local funcs=(cgroup_pids cgroup_kill cgroup_kill_and_wait)

    for func in ${funcs[@]} ; do

        try
        {
            einfo "Executing ${func} ${CGROUP}"
            ${func} ${CGROUP}

            die "${func} didn't blow up on nonexistent cgroup."
        }
        catch
        {
            :
        }
    done

}

