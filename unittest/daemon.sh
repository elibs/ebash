#!/usr/bin/env bash


#-----------------------------------------------------------------------------
# DAEMON TEST INFRASTRUCTURE NOTE
# 
# The tests below use a very tightly coupled test mechanism to ensure the 
# daemon and the test code execute in lockstep so that the tests will be more
# deterministic by removing various race conditions that existed before when
# trying to poll on the daemon status as state transitions could be missed.
# 
# This test framework essentially has two major components:
# daemon_expect and daemon_react. daemon_expect is the TEST side, whereas
# daemon_react is the part the daemon will execute.
#
# These two functions work in tandem with the help of a lockfile so that the
# test code sets up what state it expects the daemon to enter next. The 
# daemon will essentially loop inside daemon_react until the expected state
# has been setup by the test code. Once setup, the daemon will verify it's in
# the state the test code expected. If so, it will CLEAR out the state file
# to signal to the test code that it reached the desired state. Then it can
# safely return from the hook callback. The test code will then observe the
# file is empty and return from daemon_expect.
#
# It's important to note that if the daemon races around very quickly and
# gets into daemon_react again at this point the file is EMPTY and it will
# simply loop waiting for the test code to setup the next expected state.
#-----------------------------------------------------------------------------

DAEMON_LOCK="daemon.lock"
DAEMON_STATE="daemon_state"
DAEMON_HOOKS=(
    pre_start="daemon_react pre_start"
    pre_stop="daemon_react pre_stop"
    post_start="daemon_react post_start"
    post_stop="daemon_react post_stop"
    post_crash="daemon_react post_crash"
    post_abort="daemon_react post_abort"
)

daemon_react()
{
    $(declare_args actual)

    (
        while true; do

            elock ${DAEMON_LOCK}
            expected=$(cat ${DAEMON_STATE} || true)
            if [[ -z ${expected} ]]; then
                edebug "Waiting for test code to setup expected state...$(lval actual)"
                eunlock ${DAEMON_LOCK}
                sleep .5
                continue
            fi

            # Do NOT clear the state file if it's not the expected state!!
            # Because most hooks swallow errors intentionally, we can't just call die
            # here. Instead just emit error message and then sleep forever. The test code
            # itself will timeout and detect and report the failure.
            if [[ "${expected}" != "${actual}" ]]; then
                eunlock ${DAEMON_LOCK}
                eerror_stacktrace "Unexpected state $(lval expected actual)"
                sleep infinity
            fi

            >${DAEMON_STATE}
            break
        done
    )
}

daemon_expect()
{
    $(declare_args state)

    etestmsg "Waiting for daemon to reach $(lval state)"
    
    (
        SECONDS=0
        elock ${DAEMON_LOCK}
        echo "${state}" >${DAEMON_STATE}
        eunlock ${DAEMON_LOCK}

        while true; do

            elock ${DAEMON_LOCK}
            pending=$(cat "${DAEMON_STATE}" || true)
            eunlock ${DAEMON_LOCK}
            [[ -z ${pending} ]] && break

            edebug "Still waiting for daemon to reach $(lval state SECONDS)"
            assert [[ ${SECONDS} -lt 30 ]]
            sleep .5

        done
    )

    etestmsg "Daemon reached $(lval state)"
}

#-----------------------------------------------------------------------------
# DAEMON TESTS
#-----------------------------------------------------------------------------

ETEST_daemon_init()
{
    local pidfile_real="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon     \
        "${DAEMON_HOOKS[@]}"     \
        name="Infinity"          \
        cmdline="sleep infinity" \
        pidfile="${pidfile_real}"

    $(pack_import sleep_daemon)

    [[ "sleep infinity" == "${cmdline}" ]] || die "$(lval cmdline +sleep_daemon)"

    assert_eq "Infinity"       "${name}"
    assert_eq "sleep infinity" "${cmdline}"
    assert_eq "${pidfile_real}" "$(pack_get sleep_daemon pidfile)"
}

ETEST_daemon_start_stop()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
   
    etestmsg "Starting infinity daemon"
    daemon_init sleep_daemon                \
        "${DAEMON_HOOKS[@]}"                \
        name="Infinity"                     \
        cmdline="sleep infinity"            \
        cgroup="${ETEST_CGROUP}/daemon"     \
        pidfile="${pidfile}"

    daemon_start sleep_daemon
    
    # Wait for process to be running
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon

    # Now stop it and verify proper shutdown
    local pid=$(cat "${pidfile}")
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}

ETEST_daemon_cgroup()
{
    CGROUP=${ETEST_CGROUP}/daemon
    cgroup_create ${CGROUP}

    local pidfile="${FUNCNAME}.pid"

    etestmsg "Initializing daemon"
    daemon_init sleep_daemon        \
        "${DAEMON_HOOKS[@]}"        \
        name="Infinity"             \
        cmdline="sleep infinity"    \
        cgroup=${CGROUP}            \
        pidfile="${pidfile}"

    etestmsg "Running daemon"
    daemon_start sleep_daemon
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]

    local running_pids=$(cgroup_pids ${CGROUP})
    etestmsg "Daemon running $(lval CGROUP running_pids)"
    cgroup_pstree ${CGROUP}

    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    local stopped_pids=$(cgroup_pids ${CGROUP})
    assert_empty "${stopped_pids}"
}

ETEST_daemon_hooks()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon                \
        "${DAEMON_HOOKS[@]}"                \
        name="Infinity"                     \
        cmdline="sleep infinity"            \
        pidfile="${pidfile}"                \
        respawns="3"                        \
        respawn_interval="1"                \

    # START
    daemon_start sleep_daemon
    daemon_expect pre_start
    daemon_expect post_start
    assert_true daemon_running sleep_daemon
    
    # STOP
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait
    assert_false daemon_running sleep_daemon
}

# Ensure if pre_start hook fails we won't call start
ETEST_daemon_pre_start_fail()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon                      \
        name="Infinity"                           \
        cmdline="sleep infinity"                  \
        pidfile="${pidfile}"                      \
        pre_start="false"                         \
        pre_stop="touch ${FUNCNAME}.pre_stop"     \
        post_start="touch ${FUNCNAME}.post_start" \
        post_stop="touch ${FUNCNAME}.post_stop"   \
        respawns="3"                              \
        respawn_interval="1"                      \

    # START
    daemon_start sleep_daemon
    eretry -T=30s daemon_not_running sleep_daemon
    assert_not_exists ${FUNCNAME}.post_start
}

# Ensure logfile works inside daemon
ETEST_daemon_logfile()
{
    eend()
    {
        true
    }

    launch()
    {
        echo "stdout" >&1
        echo "stderr" >&2
        sleep infinity
    }
    
    local mdaemon
    daemon_init mdaemon         \
        "${DAEMON_HOOKS[@]}"    \
        name="My Daemon"        \
        cmdline="launch"        \
        logfile="launch.log"    \

    $(pack_import mdaemon logfile)

    (
        die_on_abort

        etestmsg "Starting daemon"
        daemon_start mdaemon
        daemon_expect pre_start
        daemon_expect post_start
        assert_true daemon_running mdaemon

        etestmsg "Stopping daemon"
        daemon_stop mdaemon &
        daemon_expect pre_stop
        daemon_expect post_stop
        wait
        assert_true daemon_not_running mdaemon
    )

    # Show logfile and verify state
    etestmsg "Daemon logfile:"
    cat "${logfile}"
    
    grep --silent "Starting My Daemon" "${logfile}"
    grep --silent "stdout"             "${logfile}"
    grep --silent "stderr"             "${logfile}"
    grep --silent "Stopping My Daemon" "${logfile}"
}

ETEST_daemon_respawn()
{
    touch ${DAEMON_LOCK}
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon

    daemon_init sleep_daemon                \
        "${DAEMON_HOOKS[@]}"                \
        name="Infinity"                     \
        cmdline="sleep infinity"            \
        pidfile="${pidfile}"                \
        respawns="3"                        \
        respawn_interval="300"              \

    $(pack_import sleep_daemon)
    etestmsg "Starting daemon $(lval +sleep_daemon)"
    daemon_start sleep_daemon

    # Wait for pre_start and "start" states then daemon must be running
    daemon_expect pre_start
    daemon_expect post_start
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon
    assert process_running $(cat ${pidfile})
    
    # Now kill it the specified number of respawns
    # and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        pid=$(cat "${pidfile}")
        etestmsg "Killing daemon $(lval pid iter respawns)"
        ekilltree -s=KILL ${pid}

        # Wait for "crash" state. Daemon must be NOT running now.
        daemon_expect post_crash
        assert daemon_not_running sleep_daemon
        assert process_not_running ${pid}

        # If iter == respawns break out
        [[ ${iter} -lt ${respawns} ]] || break

        # Now wait for process to respawn
        etestmsg "Waiting for daemon to respawn"
        daemon_expect pre_start
        daemon_expect post_start
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon
        assert process_running $(cat ${pidfile})
    done

    # Process should NOT be running and should NOT respawn b/c we killed it too many times
    etestmsg "Waiting for daemon to abort"
    daemon_expect post_abort
    assert_false process_running $(cat ${pidfile})
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    daemon_stop sleep_daemon
}

# Modified version of above test which gives a large enough window between kills
# such that it should keep respawning (b/c/ failed count resets)
ETEST_daemon_respawn_reset()
{
    touch ${DAEMON_LOCK}
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon                \
        "${DAEMON_HOOKS[@]}"                \
        name="Infinity"                     \
        cmdline="sleep infinity"            \
        pidfile="${pidfile}"                \
        respawns="3"                        \
        respawn_interval="0"                \

    $(pack_import sleep_daemon)
    etestmsg "Starting daemon $(lval +sleep_daemon)"
    daemon_start sleep_daemon

    # Wait for pre_start and "start" states then daemon must be running
    daemon_expect pre_start
    daemon_expect post_start
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon
    assert process_running $(cat ${pidfile})
 
    # Now kill it the specified number of respawns and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        local pid=$(cat "${pidfile}")
        etestmsg "Killing daemon $(lval pid iter respawns)"
        ekilltree -s=KILL ${pid}

        # Wait for "crash" state. Daemon must be NOT running now.
        daemon_expect post_crash
        assert daemon_not_running sleep_daemon
        assert process_not_running ${pid}

        # Now wait for process to respawn
        etestmsg "Waiting for daemon to respawn"
        daemon_expect pre_start
        daemon_expect post_start
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon
        assert process_running $(cat ${pidfile})
    done

    # Now stop it and verify proper shutdown
    etestmsg "Stopping daemon and waiting for shutdown"
    daemon_stop sleep_daemon &
    daemon_expect pre_stop
    daemon_expect post_stop
    wait 

    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}

