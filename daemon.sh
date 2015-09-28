#!/bin/bash
#
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

# daemon_init is used to initialize the options pack that all of the various
# daemon_* functions will use. This makes it easy to specify global settings
# for all of these daemon functions without having to worry about consistent
# argument parsing and argument conflicts between the various daemon_*
# functions. All of the values set into this pack are available in the caller's
# various hooks if desired. If a chroot is provided it is only used inside the
# body that calls ${cmdline}. If you need to be in the chroot to execute a given
# hook you're responsible for doing that yourself.
# 
# The following are the keys used to control daemon functionality:
#
# cgroup
#   Optional cgroup to run the daemon in. The daemon assumes ownership of ALL
#   processes in that cgroup and will kill them at shutdown time. (So give it
#   its own cgroup). This cgroup should already be created. See cgroups.sh for
#   more information.
#
# chroot
#   Optional CHROOT to run the daemon in.
#
# cmdline
#   The command line to be run as a daemon. This includes the executable as well
#   as any of its arguments.
#
# delay
#   The delay to wait, in sleep(1) syntax, before attempting to restart the daemon
#   when it exits. This should never be <1s otherwise race conditions in startup
#   and shutdown are possible. Defaults to 1s.
#
# logfile
#   Optional logfile to send all stdout and stderr to for the daemon. Since it
#   generally doesn't make sense for the stdout/stderr of the daemon to spew 
#   into the caller's stdout/stderr, these will default to /dev/null if not
#   otherwise specified.
#
# logfile_rotate
#   Optional logfile rotation parameter (see elogfile).
#
# name
#   The name of the daemon, for readability purposes. By default this will use
#   the basename of the command being executed.
#
# pidfile
#   Path to the pidfile for the daemon. By default this is the basename of the
#   command being executed, stored in /var/run.
#
# pre_start
#   Optional hook to be executed before starting the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#
# pre_stop
#   Optional hook to be executed before stopping the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#
# post_start
#   Optional hook to be executed after starting the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#
# post_stop
#   Optional hook to be exected after stopping the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#
# respawns
#   The maximum number of times to respawn the daemon command before just
#   giving up. Defaults to 10.
#
# respawn_interval
#   Amount of seconds the process must stay up for it to be considered a
#   successful start. This is used in conjunction with respawn similar to
#   upstart/systemd. If the process is respawned more than ${respawns} times
#   within ${respawn_interval} seconds, the process will no longer be respawned.
daemon_init()
{
    $(declare_args optpack)
    edebug "Initializting daemon options $(lval optpack) $@"

    # Load defaults into the pack first then add in any additional provided settings
    # Since the last key=val added to the pack will always override prior values
    # this allows caller to override the defaults.
    pack_set ${optpack}     \
        cgroup=             \
        chroot=             \
        delay=1             \
        logfile="/dev/null" \
        logfile_rotate="0"  \
        pre_start=          \
        pre_stop=           \
        post_start=         \
        post_stop=          \
        respawns=20         \
        respawn_interval=15 \
        "${@}"
    
    # Set name if missing
    local base=$(basename $(pack_get ${optpack} "cmdline" | awk '{print $1}'))
    if ! pack_contains ${optpack} "name"; then
        pack_set ${optpack} name=${base}
    fi
   
    # Set pidfile if missing
    if ! pack_contains ${optpack} "pidfile"; then
        pack_set ${optpack} pidfile="/var/run/${base}"
    fi
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

    # Don't restart the daemon if it is already running.
    if daemon_running ${optpack}; then
        local pid=$(cat ${pidfile} 2>/dev/null || true)
        einfo "${name} is already running."
        edebug "${name} is already running $(lval pid +${optpack})"
        return 0
    fi

    # Split this off into a separate sub-shell running in the background so we can
    # return to the caller.
    (
        # Setup logfile
        [[ -t 2 ]] && EINTERACTIVE=1 || EINTERACTIVE=0
        elogfile -o=1 -e=1 -r=${logfile_rotate} "${logfile}"

        # Create empty pidfile
        mkdir -p $(dirname ${pidfile})
        touch "${pidfile}"
        local runs=0

        if [[ -n ${cgroup} ]] ; then
            cgroup_move ${cgroup} ${BASHPID}
        fi

        # Check to ensure that we haven't failed running "respawns" times. If
        # we have, then don't run again. Likewise, ensure that the pidfile
        # exists. If it doesn't it likely means that we have been stopped (via
        # daemon_stop) and we really don't want to run again.
        while [[ -e "${pidfile}" && ${runs} -lt ${respawns} ]]; do

            # Info
            if [[ ${runs} -eq 0 ]]; then
                einfo "Starting ${name}"
                edebug "Starting $(lval name +${optpack})"
            else
                einfo "Restarting ${name}"
                edebug "Restarting $(lval name +${optpack})"
            fi
            
            # Increment run counter
            (( runs+=1 ))

            # Execute optional pre_start hook
            ${pre_start}

            # Construct a subprocess which bind mounts chroot mount points then executes
            # requested daemon. After the daemon completes automatically unmount chroot.
            (
                die_on_abort

                # Setup logfile
                elogfile -o=1 -e=1 -t=0 -r=${logfile_rotate} "${logfile}"

                if [[ -n ${chroot} ]]; then
                    export CHROOT=${chroot}
                    chroot_mount
                    trap_add chroot_unmount
                    chroot_cmd ${cmdline} || true
                else
                    ${cmdline} || true
                fi

            ) &>/dev/null &

            # Get the PID of the process we just created and store into requested pid file.
            local pid=$!
            echo "${pid}" > "${pidfile}"
            eend 0

            # Execute optional post_start hook
            ${post_start}

            # SECONDS is a magic bash variable keeping track of the number of
            # seconds since the shell started, we can modify it without messing
            # with the parent shell (and it will continue from where we leave
            # it).
            SECONDS=0
            wait ${pid} &>/dev/null || true
 
            # Setup logfile
            elogfile -o=1 -e=1 -t=0 -r=${logfile_rotate} "${logfile}"
           
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
                eerror "${name} crashed too many times (${runs}/${respawns}). Giving up."
                edebug "$(lval name SECONDS +${optpack})"
            else
                ewarn "${name} crashed (${current_runs}/${respawns}). Will respawn in ${delay} seconds."
                edebug "$(lval name SECONDS +${optpack})"
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
# OPTIONS:
# -s=SIGNAL  Signal to use when gracefully stopping the daemon. Default=SIGTERM.
# -t=timeout How much time to wait for process to gracefully shutdown before 
#            killing it with SIGKILL. Default=5.
# -c=timeout After everything has been sent a SIGKILL, if this daemon has
#            cgroup support, this function will continue to wait until all
#            processes in that cgroup actually disappear.  If you specify a
#            c=<some number of seconds>, we'll give up (and return an error)
#            after that many seconds have elapsed.  By default, this is 300
#            seconds (i.e. 5 minutes).  If you specify 0, this will wait forever.
daemon_stop()
{
    # Pull in our argument pack then import all of its settings for use.
    $(declare_args optpack)
    $(pack_import ${optpack})

    # Setup logfile
    [[ -t 2 ]] && EINTERACTIVE=1 || EINTERACTIVE=0
    elogfile -o=1 -e=1 -r=${logfile_rotate} "${logfile}"

    # Options
    local signal=$(opt_get s SIGTERM)
    local timeout=$(opt_get t 5)

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval name signal timeout +${optpack})"

    # If it's not running just return
    daemon_running ${optpack} \
        || { eend 0; edebug "Already stopped"; rm -rf ${pidfile}; return 0; }

    # Execute optional pre_stop hook
    ${pre_stop}

    # If it is remove the pidfile then stop the process with provided signal.
    # NOTE: It's important we remove the pidfile BEFORE we kill the process so that
    # it won't try to respawn!
    local pid=$(cat ${pidfile} 2>/dev/null || true)
    rm -f ${pidfile}
    if [[ -n ${pid} ]]; then
         
        # Try to kill the process with requested signal
        try
        {
            ekilltree -s=${signal} ${pid}
            eretry -r=5 -d=$((timeout/5)) process_not_running ${pid}
        }
        catch
        {
            ekilltree -s=SIGKILL ${pid}
            eretry -r=5 -d=$((timeout/5)) process_not_running ${pid}
        }

    fi

    process_not_running ${pid}
    eend 0

    if [[ -n ${cgroup} ]] ; then
        edebug "Waiting for all processes in $(lval cgroup) to die"
        local cgroup_timeout=$(opt_get c 300)
        cgroup_kill_and_wait -x="$$ ${BASHPID}" -s=KILL -t=${cgroup_timeout} ${cgroup}
    fi
    
    # Execute optional post_stop hook
    ${post_stop}
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
        [[ -e ${pidfile} ]] || { eend 1; edebug "Not Running (no pidfile)"; return 1; }
        local pid=$(cat ${pidfile} 2>/dev/null || true)
        [[ -z ${pid}     ]] && { eend 1; edebug "Not Running (no pid)"; return 1; }

        # Check if it's running
        process_running ${pid} || { eend 1; edebug "Not Running"; return 1; }
    
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
