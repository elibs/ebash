#!/usr/bin/env bash

ETEST_daemon_init()
{
    local pidfile_real="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon     \
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
    
    daemon_init sleep_daemon                \
        name="Infinity"                     \
        cmdline="sleep infinity"            \
        cgroup="${ETEST_CGROUP}/daemon"     \
        pidfile="${pidfile}"

    daemon_start sleep_daemon
    
    # Wait for process to be running
    eretry -r=30 -d=1 daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_daemon
    assert daemon_status  sleep_daemon

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop sleep_daemon
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}

ETEST_daemon_cgroup()
{
    CGROUP=${ETEST_CGROUP}/daemon
    cgroup_create ${CGROUP}

    local pidfile="${FUNCNAME}.pid"

    daemon_init sleep_daemon        \
        name="Infinity"             \
        cmdline="sleep infinity"    \
        cgroup=${CGROUP}            \
        pidfile="${pidfile}"

    daemon_start sleep_daemon
    eretry -r=30 -d=1 daemon_running sleep_daemon
    assert [[ -s ${pidfile} ]]

    local running_pids=$(cgroup_pids ${CGROUP})
    einfo "Daemon running $(lval CGROUP running_pids)"
    cgroup_pstree ${CGROUP}

    daemon_stop sleep_daemon
    local stopped_pids=$(cgroup_pids ${CGROUP})
    assert_empty "${stopped_pids}"
}

ETEST_daemon_respawn()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon   \
        name="Infinity"        \
        cmdline="sleep 1"      \
        pidfile="${pidfile}"   \
        respawns="3"           \
        respawn_interval="300" \

    $(pack_import sleep_daemon)
    edebug_enabled && einfo "Starting daemon $(lval +sleep_daemon)" || eprogress "Starting daemon $(lval +sleep_daemon)"
    {
        daemon_start sleep_daemon
        eretry -r=30 -d=1 daemon_running sleep_daemon
        assert [[ -s ${pidfile} ]]
        assert process_running $(cat ${pidfile})
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon

    } &>$(edebug_out)

    edebug_enabled || eprogress_kill
    
    # Now kill it the specified number of respawns
    # and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        local pid=$(cat ${pidfile})
        edebug_enabled && einfo "Killing daemon $(lval pid iter respawns)" || eprogress "Killing daemon $(lval pid iter respawns)"
        {
            ekill ${pid}
            eretry -r=30 -d=1 process_not_running ${pid}
            eretry -r=30 -d=1 daemon_not_running sleep_daemon

        } &>$(edebug_out)
        
        edebug_enabled || eprogress_kill

        # If iter == respawns break out
        [[ ${iter} -lt ${respawns} ]] || break

        # Now wait for process to respawn
        edebug_enabled || eprogress "Waiting for daemon to respawn"
        {
            eretry -r=30 -d=1 daemon_running sleep_daemon
            pid=$(cat ${pidfile})
            eretry -r=30 -d=1 process_running ${pid}
            einfo "Process respawned $(lval pid)"

        } &>$(edebug_out)

        edebug_enabled || eprogress_kill

    done

    # Process should NOT be running and should NOT respawn b/c we killed it too many times
    assert_false process_running $(cat ${pidfile})
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    daemon_stop sleep_daemon
}

# Modified version of above test which gives a large enough window between kills
# such that it should keep respawning (b/c/ failed count resets)
ETEST_daemon_respawn_reset()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon  \
        name="Infinity"       \
        cmdline="sleep 1"     \
        pidfile="${pidfile}"  \
        respawns="3"          \
        respawn_interval="0"  \

    $(pack_import sleep_daemon)
    edebug_enabled && einfo "Starting daemon $(lval +sleep_daemon)" || eprogress "Starting daemon $(lval +sleep_daemon)"
    {
        daemon_start sleep_daemon
        eretry -r=30 -d=1 daemon_running sleep_daemon
        assert [[ -s ${pidfile} ]]
        assert process_running $(cat ${pidfile})
        assert daemon_running sleep_daemon
        assert daemon_status  sleep_daemon

    } &>$(edebug_out)

    edebug_enabled || eprogress_kill
    
    # Now kill it the specified number of respawns
    # and verify it respawns each time
    for (( iter=1; iter<=${respawns}; iter++ )); do

        # Kill underlying pid
        local pid=$(cat ${pidfile})
        edebug_enabled && einfo "Killing daemon $(lval pid iter respawns)" || eprogress "Killing daemon $(lval pid iter respawns)"
        {
            ekill ${pid}
            eretry -r=30 -d=1 process_not_running ${pid}
            eretry -r=30 -d=1 daemon_not_running sleep_daemon

        } &>$(edebug_out)
        
        edebug_enabled || eprogress_kill

        # Now wait for process to respawn
        edebug_enabled || eprogress "Waiting for daemon to respawn"
        {
            eretry -r=30 -d=1 daemon_running sleep_daemon
            pid=$(cat ${pidfile})
            eretry -r=30 -d=1 process_running ${pid}
            einfo "Process respawned $(lval pid)"

        } &>$(edebug_out)

        edebug_enabled || eprogress_kill

    done

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop sleep_daemon
    assert_false daemon_running sleep_daemon
    assert_false daemon_status -q sleep_daemon
    assert_not_exists pidfile
}

ETEST_daemon_hooks()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon                      \
        name="Infinity"                           \
        cmdline="sleep 1"                         \
        pidfile="${pidfile}"                      \
        pre_start="touch ${FUNCNAME}.pre_start"   \
        pre_stop="touch ${FUNCNAME}.pre_stop"     \
        post_start="touch ${FUNCNAME}.post_start" \
        post_stop="touch ${FUNCNAME}.post_stop"   \
        respawns="3"                              \
        respawn_interval="1"                      \

    $(pack_import sleep_daemon)

    # START
    daemon_start sleep_daemon
    eretry -r=30 -d=1 daemon_running sleep_daemon
    assert_exists ${FUNCNAME}.{pre_start,post_start}
    
    # STOP
    daemon_stop sleep_daemon
    assert_exists ${FUNCNAME}.{pre_stop,post_stop}
}

# Ensure if pre_start hook fails we won't call start
ETEST_daemon_pre_start_fail()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_daemon
    
    daemon_init sleep_daemon                      \
        name="Infinity"                           \
        cmdline="sleep 1"                         \
        pidfile="${pidfile}"                      \
        pre_start="false"                         \
        pre_stop="touch ${FUNCNAME}.pre_stop"     \
        post_start="touch ${FUNCNAME}.post_start" \
        post_stop="touch ${FUNCNAME}.post_stop"   \
        respawns="3"                              \
        respawn_interval="1"                      \

    $(pack_import sleep_daemon)

    # START
    daemon_start sleep_daemon
    eretry -r=30 -d=1 daemon_not_running sleep_daemon
    assert_not_exists ${FUNCNAME}.post_start
}
