#!/bin/bash
#
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

# daemon_start will daemonize the provided command and its arguments as a
# pseudo-daemon and automatically respawn it on failure. We don't use the core
# operating system's default daemon system, as that is platform dependent and
# lacks the portability we need to daemonize things on any arbitrary system.
#
# Options:
#
# -C  Optional CHROOT to run the executable in.
#
# -c  The callback function to run prior to starting the daemon each time. If
#     the daemon crashes, or otherwise exits, and would be restarted by this
#     function then this callback is executed first.
#     Default: none
#
# -d  The delay, in seconds, to wait before attempting to restart the daemon
#     when it exits.
#     Default: 1
#
# -n  The name of the daemon, for readability purposes.
#     Default: The basename of the command issued
#
# -p  The location of the PID file for the daemon.
#     Default: The basename of the command issued, stored in /var/run/
#
# -r  The maximum number of times to start the daemon command before just
#     giving up.
#     Default: 20
#
# -w  The number of seconds to wait between starting up the daemon, and
#     checking its status.
#     Default: 1
#
# NOTES:
#  1: Due to implementation decisions, daemon_start and daemon_stop may not have
#     any overlapping options with different purposes. This is because, in many
#     places, the options passed to each function are identical and having
#     different uses for the same option would lead to unexpected behaviors in use.
daemon_start()
{
    # Parse required arguments. Any remaining options will be passed to the daemon.
    $(declare_args exe)

    # Determine optional CHROOT to run the executable in.
    local CHROOT="$(opt_get C)"

    # Determine pretty name to display from optional -n
    local name="$(opt_get n)"
    : ${name:=$(basename ${exe})}

    # Determine optional pidfile
    local pidfile="$(opt_get p)"
    : ${pidfile:=/var/run/$(basename ${exe})}

    # Determine how long to wait after the daemon dies before starting it up
    # again. NOTE - You want at least a second to ensure that in the case of a
    # daemon_stop being called, we have everything in the appropriate state
    # before starting a new process that isn't supposed to be there.
    local delay="$(opt_get d 1)"

    # Determine how many times maximum to restart the daemon.
    local restarts="$(opt_get r 20)"

    # Get callback function, if there is one, which should be run prior to
    # starting the command each time the daemon starts.
    local callback=$(opt_get c)

    # How long to wait before checking the daemon's status once started.
    local time_to_startup="$(opt_get w 1)"

    mkdir -p $(dirname ${pidfile})
    touch "${pidfile}"

    # Don't restart the daemon if it is already running.
    local currentPID=$(cat "${pidfile}" 2>/dev/null || true)
    local status=0
    if [[ -n "${currentPID}" ]]; then
        kill -0 ${currentPID} &>/dev/null || status=1
        if [[ ${status} -eq 0 ]]; then
            einfo "${name} is already running."
            edebug "$(lval CHROOT name exe pidfile) args=${@} is already running as process ${currentPID}"
            return 0 # The daemon is already running, don't start a new one
        fi
    fi

    # Split this off into a separate sub-shell running in the background so we can
    # return to the caller.
    (
        local runs=0

        # Check to ensure that we haven't failed running "restarts" times. If
        # we have, then don't run again. Likewise, ensure that the pidfile
        # exists. If it doesn't it likely means that we have been stopped (via
        # daemon_stop) and we really don't want to run again.
        while [[ ${runs} -lt ${restarts} && -e "${pidfile}" ]]; do

            # Info
            if [[ ${runs} -eq 0 ]]; then
                einfo "Starting ${name}"
                edebug "Starting $(lval CHROOT name exe pidfile) args=${@}"
            else
                einfo "Restarting ${name}"
                edebug "Restarting $(lval CHROOT name exe pidfile) args=${@}"
            fi
            runs=$((runs + 1))

            # Construct a subprocess which bind mounts chroot mount points then executes
            # requested daemon. After the daemon completes automatically unmount chroot.
            (
                ${callback}

                if [[ -n ${CHROOT} ]]; then
                    chroot_mount
                    trap_add chroot_unmount
                    chroot_cmd ${exe} ${@}
                else
                    ${exe} ${@}
                fi

            ) &>$(edebug_out) &

            # Get the PID of the process we just created and store into requested pid file.
            local pid=$!
            echo "${pid}" > "${pidfile}"

            # Give the daemon a second to startup and then check its status. If it blows
            # up immediately we'll catch the error immediately and be able to let the
            # caller know that startup failed.
            sleep ${time_to_startup}
            daemon_status -n="${name}" -p="${pidfile}" &>$(edebug_out)
            eend 0

            # SECONDS is a magic bash variable keeping track of the number of
            # seconds since the shell started, we can modify it without messing
            # with the parent shell (and it will continue from where we leave
            # it).
            SECONDS=0
            wait ${pid} &>$(edebug_out) || ewarn "Process ${name} crashed, respawning in $(lval delay) seconds"

            # Check that we have run for the minimum duration.
            # NOTE - The way this is set up, it means that the daemon must have
            #        run for at least 2 * time_to_startup.
            if [[ ${SECONDS} -ge ${time_to_startup} ]]; then
                runs=0
            fi

            # give chroot_daemon_stop a chance to get everything sorted out
            sleep ${delay}
        done
    ) &
}

# daemon_stop will find a command currently being run as a pseudo-daemon,
# terminate it with the provided signal, and clean up afterwards.
#
# Options:
# -n  The name of the daemon, for readability purposes.
#     Default: The basename of the command issued
#
# -p  The location of the PID file for the daemon.
#     Default: The basename of the command issued, stored in /var/run/
#
# -s  The signal to send the daemon to get it to quit.
#     Default: TERM
#
# NOTES:
#  1: Due to implementation decisions, daemon_start and daemon_stop may not
#     have any overlapping options with different purposes. This is because,
#     in many places, the options passed to each function are identical and
#     having different uses for the same option would lead to unexpected
#     behaviors in use.
daemon_stop()
{
    # Parse required arguments.
    $(declare_args exe)

    # Determine pretty name to display from optional -n
    local name="$(opt_get n)"
    : ${name:=$(basename ${exe})}

    # Determmine optional pidfile
    local pidfile="$(opt_get p)"
    : ${pidfile:=/var/run/$(basename ${exe})}

    # Determine optional signal to use
    local signal="$(opt_get s)"
    : ${signal:=TERM}

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval CHROOT name exe pidfile signal)"

    # If it's not running just return
    daemon_status -n="${name}" -p="${pidfile}" &>$(edebug_out) \
        || { eend 0; ewarns "Already stopped"; eend 0; rm -rf ${pidfile}; return 0; }

    # If it is running stop it with optional signal
    local pid=$(cat ${pidfile} 2>/dev/null)
    ekilltree -s=${signal} ${pid}
    rm -rf ${pidfile}
    eend 0
}

# Retrieve the status of a daemon.
#
# Options:
# -n  The name of the daemon, for readability purposes.
#     Default: The basename of the command issued
#
# -p  The location of the PID file for the daemon.
#     Default: The basename of the command issued, stored in /var/run/
#
# NOTES:
#  1: Due to implementation decisions, daemon_start, daemon_stop and daemon_status
#     may not have any conflicting options. This is because, in many places,
#     the options passed to each function are identical and having different uses
#     for the same option would lead to unexpected behaviors in use.
daemon_status()
{
    # Parse required arguments
    $(declare_args)

    # pidfile is required
    local pidfile=$(opt_get p)
    argcheck pidfile

    # Determine pretty name to display from optional -n
    local name=$(opt_get n)
    : ${name:=$(basename ${pidfile})}

    einfo "Checking ${name}"
    edebug "Checking $(lval CHROOT name pidfile)"

    # Check pidfile
    [[ -e ${pidfile} ]] || { eend 1; ewarns "Not Running (no pidfile)"; return 1; }
    local pid=$(cat ${pidfile} 2>/dev/null)
    [[ -z ${pid}     ]] && { eend 1; ewarns "Not Running (no pid)"; return 1; }

    # Send a signal to process to see if it's running
    kill -0 ${pid} &>/dev/null || { eend 1; ewarns "Not Running"; return 1; }

    # OK -- It's running
    eend 0
    return 0
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
