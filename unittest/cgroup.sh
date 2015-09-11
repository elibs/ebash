#!/usr/bin/env bash

$(esource $(dirname $0)/cgroup.sh)


ETEST_cgroup_tree()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    A=(${CGROUP}/a/{1,2,3})
    B=(${CGROUP}/b/{10,20})
    C=(${CGROUP}/c)

    cgroup_create "${A[@]}" "${B[@]}" "${C[@]}"

    einfo "Testing full cgroup_tree"
    found_tree=($(cgroup_tree))
    for item in ${A[@]} ${B[@]} ${C[@]} ; do
        assert array_contains found_tree $item
    done


    einfo "Testing that / is the root cgroup_tree"
    found_tree=($(cgroup_tree /))
    for item in ${A[@]} ${B[@]} ${C[@]} ; do
        assert array_contains found_tree $item
    done

    einfo "Testing cgroup_tree a"
    found_tree=($(cgroup_tree ${CGROUP}/a))
    for item in ${A[@]} ; do
        assert array_contains found_tree $item
    done

    einfo "Testing cgroup_tree with multiple parameters"
    found_tree=($(cgroup_tree ${CGROUP}/b ${CGROUP}/c))
    for item in ${B[@]} ${C[@]} ; do
        assert array_contains found_tree $item
    done
}

ETEST_cgroup_pstree()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}/{a,b,c}
    (
        cgroup_move ${CGROUP} ${BASHPID}

        sleep infinity&
        sleep1=$!
        cgroup_move ${CGROUP}/a ${sleep1}

        sleep infinity&
        sleep2=$!
        cgroup_move ${CGROUP}/b ${sleep2}

        local output="$(EDEBUG=0 cgroup_pstree ${CGROUP} 2>&1 )"

        einfo "Actual pstree output"
        echo "${output}"

        # Make sure the output contains some handy strings that I know should
        # be there, such as the PIDs of the two sleeps.
        (
            echo ${output} | grep -P '\b'${sleep1}'\b' 
            echo ${output} | grep -P '\b'${sleep2}'\b' 
            echo ${output} | grep "${CGROUP}/a"
            echo ${output} | grep "${CGROUP}/b"
            echo ${output} | grep "${CGROUP}/c"
        ) >/dev/null
    )
}

ETEST_cgroup_destroy_recursive()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}/{a,b,c,d}
    assert cgroup_exists ${CGROUP}/{a,b,c,d}

    cgroup_destroy -r ${CGROUP}

    assert ! cgroup_exists ${CGROUP}/{a,b,c,d} ${CGROUP}
}

ETEST_cgroup_create_destroy()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

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
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}
    cgroup_exists ${CGROUP}
    cgroup_create ${CGROUP}
    cgroup_exists ${CGROUP}
}

ETEST_cgroup_exists()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

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
}

     
ETEST_cgroup_pids_recursive()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP} ${CGROUP}/subgroup
    (
        cgroup_move ${CGROUP} ${BASHPID}
        PARENT_PID=${BASHPID}
        (
            cgroup_move ${CGROUP}/subgroup ${BASHPID}

            local allPids
            allPids=($(cgroup_pids -r ${CGROUP}))

            einfo BASHPID=${BASHPID} $(lval allPids PARENT_PID)

            assert_true array_contains allPids ${BASHPID}
            assert_true array_contains allPids ${PARENT_PID}
        )
    )
}

ETEST_cgroup_move_multiple_pids_at_once()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    cgroup_create ${CGROUP}

    local PIDS=()
    sleep infinity &
    PIDS+=($!)
    sleep infinity &
    PIDS+=($!)

    einfo "Started sleep processes $(lval PIDS)"
    cgroup_move ${CGROUP} "${PIDS[@]}"

    local foundPids
    foundPids=($(cgroup_pids -r ${CGROUP}))
    for pid in "${PIDS[@]}" ; do
        assert_true array_contains foundPids ${pid}
    done
}

ETEST_cgroup_pids_except()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}
    (
        cgroup_move ${CGROUP} ${BASHPID}

        local found_pids pid=${BASHPID}
        array_init found_pids "$(cgroup_pids -r -x="${pid}" ${CGROUP})"
        ewarn "${pid} found: $(lval found_pids)"
        assert_false array_contains found_pids "${pid}"
    )
}

ETEST_cgroup_pids_missing_cgroup()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}/a
    (
        local found_pids pid=${BASHPID} rc=0

        cgroup_move ${CGROUP}/a ${pid}

        # cgroup_pids should echo the proper pids to stdout
        array_init found_pids "$(cgroup_pids -r ${CGROUP}/{a,b,c} || true)"
        edebug "$(lval found_pids pid CGROUP)"
        assert array_contains found_pids ${pid}

        # And it should return an error code, specifically two for the two
        # cgroups (b and c) that do not exist
        cgroup_pids -r ${CGROUP}/{a,b,c} || rc=$?
        assert [[ ${rc} -eq 2 ]]
    )
}

ETEST_cgroup_move_ignores_empties()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    cgroup_create ${CGROUP}
    (
        # Adding an empty string to the tasks file in the cgroup filesystem would
        # typically blow up.  cgroup_move intentionally skips empty strings to make
        # life a bit easier.
        cgroup_move ${CGROUP} "" ${BASHPID} ""
    )
}

ETEST_cgroup_pids_checks_all_subsystems()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"

    cgroup_create ${CGROUP}

    # Create a process in the cgroup
    sleep infinity&
    local pid=$!
    cgroup_move ${CGROUP} ${pid}

    einfo "Created a sleep process $(lval pid)"

    # Remove it from the cgroup in a single subsystem (arbitrarily #1)
    echo ${pid} > /sys/fs/cgroup/${CGROUP_SUBSYSTEMS[1]}/tasks

    # Make sure it still shows up in the list of pids
    foundPids=($( cgroup_pids -r ${CGROUP}))
    einfo "$(lval pid foundPids)"
    einfo "$(ps hp $pid)"

    assert_true array_contains foundPids ${pid}

}

ETEST_cgroup_kill_excepts_current_process()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    cgroup_create ${CGROUP}


    (
        # NOTE: You must add ${BASHPID}, not $$ here because we only want the
        # subshell inside this cgroup

        cgroup_move ${CGROUP} ${BASHPID}
        einfo "Joined cgroup $(lval CGROUP) \$\$=$$ \$BASHPID=${BASHPID} pids=$(cgroup_pids -r ${CGROUP})"
        cgroup_kill_and_wait -x="${BASHPID} $$" ${CGROUP}

        einfo "Subshell still exists after cgroup_kill_and_wait"
    )

    [[ $? -eq 0 ]] || die "Subshell should not have been killed by cgroup_kill, but it was."
}

ETEST_cgroup_functions_like_empty_cgroups()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    cgroup_create ${CGROUP}

    local empty
    empty=$(cgroup_pids -r ${CGROUP})
    assert_empty empty

    cgroup_kill ${CGROUP}
    cgroup_kill_and_wait ${CGROUP}

    cgroup_destroy ${CGROUP}
}

ETEST_cgroup_functions_blow_up_on_nonexistent_cgroups()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    cgroup_create ${CGROUP}

    local funcs=(cgroup_pids -r cgroup_kill cgroup_kill_and_wait)

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

ETEST_cgroup_kill_and_destroy_ingore_nonexistent_cgroups()
{
    CGROUP=${FUNCNAME}
    trap_add "cgroup_kill_and_wait ${CGROUP} ; cgroup_destroy -r ${CGROUP}"
    local CGROUP=cgroup_kill_and_destroy_ignore_nonexistent_cgroups

    # Even if it had accidentally been created, if you destroy the cgroup twice
    # it definitely should've been gone once
    cgroup_destroy ${CGROUP}
    cgroup_destroy ${CGROUP}

    # And now that it's gone, make sure kill can deal with that, too
    cgroup_kill ${CGROUP}
}
