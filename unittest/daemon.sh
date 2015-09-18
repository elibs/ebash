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
    eretry daemon_running sleep_options
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})
    assert daemon_running sleep_options
    assert daemon_status  sleep_options

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop sleep_options
    eretry process_not_running "${pid}"
    assert_false daemon_running sleep_options
    assert_false daemon_status -q sleep_options
    assert_not_exists pidfile

    sleep 1
}

DISABLED_ETEST_daemon_respawn()
{
    local pidfile="${FUNCNAME}.pid"
    local sleep_options
    
    daemon_init sleep_options \
        name="Infinity"       \
        cmdline="sleep 1"     \
        pidfile="${pidfile}"  \
        respawns="10"         \
        respawn_interval="70" \

    einfo "Starting an daemon $(lval +sleep_options)"
    daemon_start sleep_options
}

