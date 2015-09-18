#!/usr/bin/env bash

$(esource daemon.sh)

ETEST_daemon_start_stop()
{
    local exe="sleep infinity"
    local pidfile="${FUNCNAME}.pid"
    local daemon_args=( "-n=Infinity" "-p=${pidfile}" )
    daemon_start "${daemon_args[@]}" "${exe}"
    
    # Wait for process to be running
    eretry daemon_status "${daemon_args[@]}" "${exe}"
    assert [[ -s ${pidfile} ]]
    assert process_running $(cat ${pidfile})

    # Now stop it and verify proper shutdown
    local pid=$(cat ${pidfile})
    daemon_stop "${daemon_args[@]}" "${exe}"
    eretry process_not_running "${pid}"
    assert_false daemon_status "${daemon_args[@]}" "${exe}"
    assert_not_exists pidfile

    sleep 5
}

DISABLED_ETEST_daemon_respawn()
{
    local exe="sleep 1"
    local respawns=10
    local wait_time=70

    einfo "Starting an exit daemon that will respawn ${respawns} times"
    local daemon_args=( "-n=Count" "-p=${DAEMON_PIDFILE}" "-r=${respawns}" "-c=daemon_callback" )
    daemon_start "${daemon_args[@]}" "${exe}"
    test_wait ${wait_time}
    local count=$(cat "${DAEMON_OUTPUT}" | wc -l)
    einfo "$(lval count)"
    [[ ${count} -ge $(( ${respawns} / 2 )) ]] || die "$(lval count) -ge $(( ${respawns} / 2 )) evaluated to false"
    rm -f "${DAEMON_OUTPUT}" "${DAEMON_PIDFILE}"

    daemon_args=( "-n=Count" "-p=${DAEMON_PIDFILE}" "-c=daemon_callback" )
    einfo "Starting an exit daemon that will respawn the default number (20) times"
    daemon_start "${daemon_args[@]}" "${exe}"
    test_wait ${wait_time}
    count=$(cat "${DAEMON_OUTPUT}" | wc -l)
    einfo "$(lval count)"
    [[ ${count} -ge 10 ]] || die "$(lval count) -ge 10 evaluated to false."
    rm -f "${DAEMON_OUTPUT}" "${DAEMON_PIDFILE}"
}


