#!/usr/bin/env bash

$(esource daemon.sh)

ETEST_daemon_init()
{
    local pidfile_real="${FUNCNAME}.pid"
    local sleep_options
    
    daemon_init sleep_options    \
        name="Infinity"          \
        cmdline="sleep infinity" \
        pidfile="${pidfile_real}"

    $(pack_import sleep_options)

    [[ "sleep infinity" == "${cmdline}" ]] || die "$(lval cmdline +sleep_options)"

    assert_eq "Infinity"       "${name}"
    assert_eq "sleep infinity" "${cmdline}"
    assert_eq "${pidfile_real}" "$(pack_get sleep_options pidfile)"
}

ETEST_daemon_start_stop()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_options
    
    daemon_init sleep_options    \
        name="Infinity"          \
        cmdline="sleep infinity" \
        pidfile="${pidfile}"

    daemon_start sleep_options
    
    # Wait for process to be running
    eretry -r=30 -d=1 daemon_running sleep_options
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_options
    assert daemon_status  sleep_options

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop sleep_options
    eretry -r=30 -d=1 process_not_running "${pid}"
    assert_false daemon_running sleep_options
    assert_false daemon_status -q sleep_options
    assert_not_exists pidfile

    sleep 1
}

ETEST_daemon_respawn()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_options
    
    daemon_init sleep_options \
        name="Infinity"       \
        cmdline="sleep 1"     \
        pidfile="${pidfile}"  \
        respawns="3"          \
        respawn_interval="30" \

    $(pack_import sleep_options)
    edebug_enabled && einfo "Starting daemon $(lval +sleep_options)" || eprogress "Starting daemon $(lval +sleep_options)"
    {
        daemon_start sleep_options
        eretry -r=30 -d=1 daemon_running sleep_options
        assert [[ -s ${pidfile} ]]
        assert process_running $(cat ${pidfile})
        assert daemon_running sleep_options
        assert daemon_status  sleep_options

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
            eretry -r=30 -d=1 daemon_not_running sleep_options

        } &>$(edebug_out)
        
        edebug_enabled || eprogress_kill

        # If iter == respawns break out
        [[ ${iter} -lt ${respawns} ]] || break

        # Now wait for process to respawn
        edebug_enabled || eprogress "Waiting for daemon to respawn"
        {
            eretry -r=30 -d=1 daemon_running sleep_options
            pid=$(cat ${pidfile})
            eretry -r=30 -d=1 process_running ${pid}
            einfo "Process respawned $(lval pid)"

        } &>$(edebug_out)

        edebug_enabled || eprogress_kill

    done

    # Process should NOT be running and should NOT respawn b/c we killed it too many times
    assert_false process_running $(cat ${pidfile})
    assert_false daemon_running sleep_options
    assert_false daemon_status -q sleep_options
    daemon_stop sleep_options

    sleep 1
}

# Modified version of above test which gives a large enough window between kills
# such that it should keep respawning (b/c/ failed count resets)
ETEST_daemon_respawn_reset()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_options
    
    daemon_init sleep_options \
        name="Infinity"       \
        cmdline="sleep 1"     \
        pidfile="${pidfile}"  \
        respawns="3"          \
        respawn_interval="1"  \

    $(pack_import sleep_options)
    edebug_enabled && einfo "Starting daemon $(lval +sleep_options)" || eprogress "Starting daemon $(lval +sleep_options)"
    {
        daemon_start sleep_options
        eretry -r=30 -d=1 daemon_running sleep_options
        assert [[ -s ${pidfile} ]]
        assert process_running $(cat ${pidfile})
        assert daemon_running sleep_options
        assert daemon_status  sleep_options

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
            eretry -r=30 -d=1 daemon_not_running sleep_options

        } &>$(edebug_out)
        
        edebug_enabled || eprogress_kill

        # Now wait for process to respawn
        edebug_enabled || eprogress "Waiting for daemon to respawn"
        {
            eretry -r=30 -d=1 daemon_running sleep_options
            pid=$(cat ${pidfile})
            eretry -r=30 -d=1 process_running ${pid}
            einfo "Process respawned $(lval pid)"

        } &>$(edebug_out)

        edebug_enabled || eprogress_kill

    done

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop sleep_options
    eretry -r=30 -d=1 process_not_running "${pid}"
    assert_false daemon_running sleep_options
    assert_false daemon_status -q sleep_options
    assert_not_exists pidfile

    sleep 1
}

