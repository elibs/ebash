#!/bin/bash
#
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

# daemon_init is used to initialize the options pack that all of the various
# daemon_* functions will use. This makes it easy to specify global settings
# for all of these daemon functions without having to worry about consistent
# argument parsing and argument conflicts between the various daemon_*
# functions.
# 
# The following are the keys used to control daemon functionality:
#
# chroot:   Optional CHROOT to run the daemon in.
#
# cmdline:  The commandlnie to be run as a daemon. This includes the executable 
#           as well as any of its arguments.
#
# callback: Optional callback function to run prior to starting the daemon each
#           time. If the daemon crashes or exits and needs to be respawned then
#           this callback will be called first.
#
# delay:    The delay, in seconds, to wait before attempting to restart the daemon
#           when it exits. Generally this should never be <1 otherwise race 
#           conditions in startup/shutdown are possible. Defaults to 1.
#
# name:     The name of the daemon, for readability purposes. By default this will
#           use the basename of the command being executed.
#
# pidfile:  Path to the pidfile for the daemon. By default this is the basename
#           of the command being executed, stored in /var/run.
#
# signal:   Signal to use when stopping the daemon. Defaults to SIGTERM.
#
# respawns: The maximum number of times to respawn the daemon command before just
#           giving up. Defaults to 20.
#
# respawn_interval: Amount of seconds the process must stay up for it to be considered a
#           successful start. This is used in conjunction with respawn similar to
#           upstart/systemd. If the process is respawned more than ${respawns} times
#           within ${respawn_interval} seconds, the process will no longer be respawned.
daemon_init()
{
    $(declare_args optpack)
    edebug "Initializting daemon options $(lval optpack) $@"

    # Load defaults into the pack first then add in any additional provided settings
    # Since the last key=val added to the pack will always override prior values
    # this allows caller to override the defaults.
    pack_set ${optpack} chroot= callback= delay=1 respawns=20 respawn_interval=15 signal=SIGTERM "${@}"
    
    # Set name if missing
    local base=$(basename $(pack_get ${optpack} "cmdline" | awk '{print $1}'))
    if ! pack_contains ${optpack} "name"; then
        pack_set ${optpack} name=${base}
    fi
   
    # Set pidfile if missing
    if ! pack_contains ${optpack} "pidfile"; then
        pack_set ${optpack} pidfile="/var/run/${base}"
    fi

    pack_print ${optpack} &>$(edebug_out)
}

# daemon_start will daemonize the provided command and its arguments as a
# pseudo-daemon and automatically respawn it on failure. We don't use the core
# operating system's default daemon system, as that is platform dependent and
# lacks the portability we need to daemonize things on any arbitrary system.
#
# For options which control daemon_start functionality please see daemon_init.
#
daemon_start()
{
    # Pull in our argument pack then import all of its settings for use.
    $(declare_args optpack)
    $(pack_import ${optpack})

    # Create empty pidfile
    local pid
    mkdir -p $(dirname ${pidfile})
    touch "${pidfile}"

    # Don't restart the daemon if it is already running.
    if daemon_running ${optpack}; then
        einfo "${name} is already running."
        edebug "${name} is already running $(lval pid +${optpack})"
        return 0
    fi

    # Split this off into a separate sub-shell running in the background so we can
    # return to the caller.
    (
        local runs=0

        # Check to ensure that we haven't failed running "respawns" times. If
        # we have, then don't run again. Likewise, ensure that the pidfile
        # exists. If it doesn't it likely means that we have been stopped (via
        # daemon_stop) and we really don't want to run again.
        while [[ ${runs} -lt ${respawns} && -e "${pidfile}" ]]; do

            # Info
            if [[ ${runs} -eq 0 ]]; then
                einfo "Starting ${name}"
                edebug "Starting $(lval name +${optpack})"
            else
                einfo "Restarting ${name}"
                edebug "Restarting $(lval name +${optpack})"
            fi
            
            runs=$((runs + 1))

            # Construct a subprocess which bind mounts chroot mount points then executes
            # requested daemon. After the daemon completes automatically unmount chroot.
            (
                die_on_abort

                ${callback}

                if [[ -n ${chroot} ]]; then
                    export CHROOT=${chroot}
                    chroot_mount
                    trap_add chroot_unmount
                    chroot_cmd ${cmdline} || true
                else
                    ${cmdline} || true
                fi

            ) &>$(edebug_out) &

            # Get the PID of the process we just created and store into requested pid file.
            pid=$!
            echo "${pid}" > "${pidfile}"
            eend 0

            # SECONDS is a magic bash variable keeping track of the number of
            # seconds since the shell started, we can modify it without messing
            # with the parent shell (and it will continue from where we leave
            # it).
            SECONDS=0
            wait ${pid} &>/dev/null || true
            
            # If we were gracefully shutdown then don't do anything further
            [[ -e "${pidfile}" ]] || { edebug "Gracefully stopped"; exit 0; }
 
            # Check that we have run for the minimum duration so we can decide
            # if we're going to respawn or not.
            local current_runs=${runs}
            if [[ ${SECONDS} -ge ${respawn_interval} ]]; then
                runs=0
            fi
           
            # Log specific message
            if [[ ${runs} -ge ${respawns} ]]; then
                eerror "Process ${name} crashed too many times (${runs}/${respawns}). Giving up."
            else
                ewarn "Process ${name} crashed (${current_runs}/${respawns}). Will respawn in ${delay} seconds."
            fi

            # give daemon_stop a chance to get everything sorted out
            sleep ${delay}
        done
    ) &
}

# daemon_stop will find a command currently being run as a pseudo-daemon,
# terminate it with the provided signal, and clean up afterwards.
#
# For options which control daemon_start functionality please see daemon_init.
#
daemon_stop()
{
    # Pull in our argument pack then import all of its settings for use.
    $(declare_args optpack)
    $(pack_import ${optpack})

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval name +${optpack})"

    # If it's not running just return
    daemon_running ${optpack} \
        || { eend 0; ewarns "Already stopped"; eend 0; rm -rf ${pidfile}; return 0; }

    # If it is remove the pidfile then stop the process with provided signal.
    # NOTE: It's important we remove the pidfile BEFORE we kill the process so that
    # it won't try to respawn!
    local pid=$(cat ${pidfile} 2>/dev/null || true)
    rm -f ${pidfile}
    ekilltree -s=${signal} ${pid}
    eend 0
}

# Retrieve the status of a daemon.
#
# For options which control daemon_start functionality please see daemon_init.
#
# Options:
# -q=(0|1) Make the status function quiet and send everything to /dev/null.
daemon_status()
{
    # Pull in our argument pack then import all of its settings for use.
    $(declare_args optpack)
    $(pack_import ${optpack})

    local redirect
    opt_true "q" && redirect="/dev/null" || redirect="/dev/stderr"

    {
        einfo "Checking ${name}"
        edebug "Checking $(lval name +${optpack})"

        # Check pidfile
        [[ -e ${pidfile} ]] || { eend 1; ewarns "Not Running (no pidfile)"; return 1; }
        local pid=$(cat ${pidfile} 2>/dev/null || true)
        [[ -z ${pid}     ]] && { eend 1; ewarns "Not Running (no pid)"; return 1; }

        # Check if it's running
        process_running ${pid} || { eend 1; ewarns "Not Running"; return 1; }
    
        # OK -- It's running
        eend 0

    } &>${redirect}
    
    return 0
}

# Check if the daemon is running. This is just a convenience wrapper around
# "daemon_status -q". This is a little more convenient to use in scripts where you
# only care if it's running and don't want to have to suppress all the output from
# daemon_status.
daemon_running()
{
    daemon_status -q "${@}"
}

# Check if the daemon is not running
daemon_not_running()
{
    ! daemon_status -q "${@}"
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
