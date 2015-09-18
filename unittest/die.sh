#!/usr/bin/env bash

ETEST_die_subprocesses()
{
    try
    {
        # Create a bunch of background processes
        sleep infinity& echo "$!"        >> pids
        sleep infinity& echo "$!"        >> pids
        bash -c 'sleep 1000' & echo "$!" >> pids
        bash -c 'sleep 4000' & echo "$!" >> pids

        einfo "Processes are running..."
        cat pids

        die "Killing try block"
    }
    catch
    {
        true
    }

    for pid in $(cat pids); do
        eretry -t=2s process_not_running ${pid}
    done
}

# Ensure if we call die() that any subshell registered traps are executed before death.
ETEST_die_traps()
{
    local fname="die_traps.txt"
    touch "${fname}"

    try
    {
        trap_add "rm ${fname}"
        die "Aborting subshell" 
    }
    catch
    {
        true
    }

    assert [[ ! -e ${fname} ]]
}

# Ensure if we have traps registered in our parent process that those are executed before death.
ETEST_die_traps_parent()
{ 
    local fname1="die_traps_parent.txt"
    local fname2="die_traps_child.txt"

    (
        touch "${fname1}"
        trap_add "echo 'PARENT: Removing ${fname1}'; rm -f ${fname1}"

        (
            touch "${fname2}"
            trap_add "echo 'CHILD: Removing ${fname2}'; rm -f ${fname2}"
            die "Aborting subshell"

        ) || true

    ) || true

    assert [[ ! -e ${fname1} ]]
    assert [[ ! -e ${fname2} ]]
}

# Ensure trap_add works properly and appends traps to existing ones.
# DT-72: NOTE: This doesn't work. It probably never worked ever.
# See: https://solidfire.atlassian.net/browse/DT-72
DISABLED_ETEST_trap_add()
{
    trap - SIGUSR1
    trap_add 'echo t1'
    assert_eq "echo t1; " "$(extract_trap_cmd SIGUSR1)"

    foo()
    {
        trap_add "echo t2"
        assert_eq "echo t2; echo t1; " "$(extract_trap_cmd SIGUSR1)"

        (
            assert_eq "echo t2; echo t1; " "$(extract_trap_cmd SIGUSR1)"
            trap_add "echo t3"
            assert_eq "echo t3; echo t2; echo t1; " "$(extract_trap_cmd SIGUSR1)"
            trap_add "echo t4"
            assert_eq "echo t4; echo t3; echo t2; echo t1; " "$(extract_trap_cmd SIGUSR1)"
        )

        assert_eq "echo t2; echo t1; " "$(extract_trap_cmd SIGUSR1)"
    }

    declare -f -t foo
    
    foo
    assert_eq "echo t1; " "$(extract_trap_cmd SIGUSR1)"
}

# Ensure trap_add works properly and appends traps to existing ones.
# DT-72: NOTE: This doesn't work. It probably never worked ever.
# See: https://solidfire.atlassian.net/browse/DT-72
DISABLED_ETEST_trap_add_invoke()
{
    trap - SIGUSR1
    trap_add 'echo t1'

    foo()
    {
        trap_add "echo t2"

        (
            trap_add "echo t3"
            trap_add "echo t4"
        )

        kill -SIGUSR1 $BASHPID
    }

    foo

}
