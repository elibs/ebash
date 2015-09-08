#!/usr/bin/env bash

$(esource $(dirname $0)/cgroup.sh)


ETEST_cgroup_tree()
{
    cgroup_tree distbox
}

ETEST_cgroup_destroy_recursive()
{
    CGROUP=cgroup_destroy_recursive

    cgroup_create ${CGROUP}/{a,b,c,d}
    assert cgroup_exists ${CGROUP}/{a,b,c,d}

    cgroup_destroy -r ${CGROUP}

    assert ! cgroup_exists ${CGROUP}/{a,b,c,d} ${CGROUP}

}

ETEST_cgroup_create_destroy()
{
    CGROUP=cgroup_create_destroy

    # Create cgroup and make sure the directories exist in each subsystem
    cgroup_create ${CGROUP}
    for subsys in ${CGROUP_SUBSYSTEMS[@]} ; do
        assert [[ -d /sys/fs/cgroup/${subsys}/${CGROUP} ]]
    done

    cgroup_exists ${CGROUP}

    # And make sure they get cleaned up
    cgroup_destroy ${CGROUP}
    for subsys in ${CGROUP_SUBSYSTEMS[@]} ; do
        assert [[ ! -d /sys/fs/cgroup/${subsys}/${CGROUP} ]]
    done
}

ETEST_cgroup_create_twice()
{
    CGROUP=cgroup_create_twice
    cgroup_create ${CGROUP}
    cgroup_exists ${CGROUP}
    cgroup_create ${CGROUP}
    cgroup_exists ${CGROUP}

    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_exists()
{
    CGROUP=_cgroup_exists

    einfo "Checking detection of destroyed cgroup"
    cgroup_destroy -r ${CGROUP}
    cgroup_exists ${CGROUP} || rc=$?
    assert [[ ${rc} -eq 1 ]]

    einfo "Checking detection of created cgroup"
    rc=0
    cgroup_create ${CGROUP}
    assert cgroup_exists ${CGROUP}

    einfo "Generates special exit code for inconsistent cgroup"
    rc=0
    rmdir /sys/fs/cgroup/${CGROUP_SUBSYSTEMS[0]}/${CGROUP}
    find /sys/fs/cgroup -name "${CGROUP}" -ls
    cgroup_exists ${CGROUP} || rc=$?
    assert [[ ${rc} -eq 2 ]]

    cgroup_destroy ${CGROUP}
}

     
ETEST_cgroup_pids_recursive()
{
    CGROUP=cgroup_pids_recursive
    cgroup_create ${CGROUP} ${CGROUP}/subgroup
    (
        cgroup_move ${CGROUP} ${BASHPID}
        PARENT_PID=${BASHPID}
        (
            cgroup_move ${CGROUP}/subgroup ${BASHPID}

            local allPids
            allPids=($(cgroup_pids ${CGROUP}))

            einfo BASHPID=${BASHPID} $(lval allPids PARENT_PID)

            assert_true array_contains allPids ${BASHPID}
            assert_true array_contains allPids ${PARENT_PID}
        )
    )
    cgroup_destroy -r ${CGROUP}
}

ETEST_cgroup_move_multiple_pids_at_once()
{
    CGROUP=cgroup_move_multiple_pids_at_once 
    cgroup_create ${CGROUP}

    local PIDS=()
    sleep infinity &
    PIDS+=($!)
    sleep infinity &
    PIDS+=($!)

    einfo "Started sleep processes $(lval PIDS)"
    cgroup_move ${CGROUP} "${PIDS[@]}"

    local foundPids
    foundPids=($(cgroup_pids ${CGROUP}))
    for pid in "${PIDS[@]}" ; do
        assert_true array_contains foundPids ${pid}
    done


    cgroup_kill ${CGROUP}
}

ETEST_cgroup_pids_except()
{
    CGROUP=cgroup_pids_except
    cgroup_create ${CGROUP}
    (
        cgroup_move ${CGROUP} ${BASHPID}

        local found_pids pid=${BASHPID}
        array_init found_pids "$(cgroup_pids -x="${pid}" ${CGROUP})"
        ewarn "${pid} found: $(lval found_pids)"
        assert_false array_contains found_pids "${pid}"
    )
    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_pids_missing_cgroup()
{
    CGROUP=cgroup_pids_missing_cgroup
    cgroup_create ${CGROUP}/a
    (
        local found_pids pid=${BASHPID} rc=0

        cgroup_move ${CGROUP}/a ${pid}

        # cgroup_pids should echo the proper pids to stdout
        array_init found_pids "$(cgroup_pids ${CGROUP}/{a,b,c} || true)"
        edebug "$(lval found_pids pid CGROUP)"
        assert array_contains found_pids ${pid}

        # And it should return an error code, specifically two for the two
        # cgroups (b and c) that do not exist
        cgroup_pids ${CGROUP}/{a,b,c} || rc=$?
        assert [[ ${rc} -eq 2 ]]
    )
    cgroup_destroy ${CGROUP}/a
}

ETEST_cgroup_move_ignores_empties()
{
    CGROUP=cgroup_move_ignores_empties
    cgroup_create ${CGROUP}
    (
        # Adding an empty string to the tasks file in the cgroup filesystem would
        # typically blow up.  cgroup_move intentionally skips empty strings to make
        # life a bit easier.
        cgroup_move ${CGROUP} "" ${BASHPID} ""
    )
    cgroup_kill_and_wait ${CGROUP}
    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_pids_checks_all_subsystems()
{
    local CGROUP=cgroup_pids_checks_all_subsystems
    cgroup_create ${CGROUP}

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

    cgroup_kill_and_wait ${CGROUP}
    cgroup_destroy ${CGROUP}

}

ETEST_cgroup_kill_excepts_current_process()
{
    local CGROUP=cgroup_kill_excepts_current_process
    cgroup_create ${CGROUP}

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
    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_functions_like_empty_cgroups()
{
    local CGROUP=cgroup_functions_like_empty_cgroups
    cgroup_create ${CGROUP}

    local empty
    empty=$(cgroup_pids ${CGROUP})
    assert_empty empty

    cgroup_kill ${CGROUP}
    cgroup_kill_and_wait ${CGROUP}

    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_functions_blow_up_on_nonexistent_cgroups()
{
    local CGROUP=cgroup_functions_blow_up_on_nonexistent_cgroups
    cgroup_create ${CGROUP}

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
    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_kill_and_destroy_ingore_nonexistent_cgroups()
{
    local CGROUP=cgroup_kill_and_destroy_ignore_nonexistent_cgroups

    # Even if it had accidentally been created, if you destroy the cgroup twice
    # it definitely should've been gone once
    cgroup_destroy ${CGROUP}
    cgroup_destroy ${CGROUP}

    # And now that it's gone, make sure kill can deal with that, too
    cgroup_kill ${CGROUP}
}
