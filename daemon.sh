#!/bin/bash
#
# Copyright 2012-2013, SolidFire, Inc. All rights reserved.
#

[[ ${__BU_OS} == Linux ]] || return 0

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
# bindmounts
#   Optional whitespace separated list of additional paths which whould be
#   bind mounted into the chroot by the daemon process during daemon_start.
#   A trap will be setup so that the bind mounts are automatically unmounted
#   when the process exits. The syntax for these bind mounts allow mounting
#   them into alternative paths inside the chroot using a colon to delimit
#   the source path outside the chroot and the desired mount point inside the
#   chroot. (e.g. /var/log/kern.log:/var/log/host_kern.log)
#
# cgroup
#   Optional cgroup to run the daemon in. If the cgroup does not exist it will
#   be created for you. The daemon assumes ownership of ALL processes in that
#   cgroup and will kill them at shutdown time. (So give it its own cgroup).
#   See cgroups.sh for more information.
#
# chroot
#   Optional CHROOT to run the daemon in. chroot_cmd will be used to execute
#   the provided command line but all other hooks will be performed outside
#   of the chroot. Though the CHROOT variable will be availble in the hooks
#   if needed.
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
# logfile_count
#   Maximum number of logfiles to keep (defaults to 5). See elogfile and
#   elogrotate for more details.
#
# logfile_size
#   Maximum logfile size before logfiles should be rotated. This defaults to
#   zero such that if you provide any logfile it will be rotated automatially.
#   See elogfile and elogrotate for more details.
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
#   If this hook fails, the daemon will NOT be started or respawned.
#
# pre_stop
#   Optional hook to be executed before stopping the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#   Any errors from this hook are ignored.
#
# post_start
#   Optional hook to be executed after starting the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#   Any errors from this hook are ignored.
#
# post_stop
#   Optional hook to be exected after stopping the daemon. Must be a single
#   command to be executed. If more complexity is required use a function.
#   Any errors from this hook are ignored.
#
# post_crash
#   Optional hook to be executed after the daemon stops abnormally (i.e not
#   through daemon_stop).  Errors from this hook are ignored.
#
# post_abort
#   Optional hook to be called after the daemon aborts due to crashing too
#   many times. Errors from this hook are ignored.
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
#
# netns_name
#   Network namespce to run the daemon in.  The namespace must be created and
#   properly configured before use.  if you use this, you need to source
#   netns.sh from bashutils prior to calling daemon_start
#
daemon_init()
{
    $(opt_parse optpack)

    # Load defaults into the pack first then add in any additional provided settings
    # Since the last key=val added to the pack will always override prior values
    # this allows caller to override the defaults.
    pack_set ${optpack}     \
        bindmounts=         \
        cgroup=             \
        chroot=             \
        delay=1             \
        logfile=            \
        logfile_count=0     \
        logfile_size=0      \
        pre_start=          \
        pre_stop=           \
        post_start=         \
        post_stop=          \
        post_crash=         \
        post_abort=         \
        respawns=20         \
        respawn_interval=15 \
        netns_name=         \
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

    return 0
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
    $(opt_parse optpack)
    $(pack_import ${optpack})

    # Don't restart the daemon if it is already running.
    if daemon_running ${optpack}; then
        local pid=$(cat ${pidfile} 2>/dev/null || true)
        einfo "${name} is already running"
        edebug "${name} is already running $(lval pid %${optpack})"
        eend 0
        return 0
    fi

    # create variable to hold either "" or the command prefix to run the daemon
    # in a network namespace.
    local netns_cmd_prefix=
    if [[ -n ${netns_name} ]] ; then
        if ! netns_exists ${netns_name} ; then
            die "Network namespace '${netns_name}' doesn't exist"
        fi
        netns_cmd_prefix="netns_exec ${netns_name}"
    fi


    # Split this off into a separate sub-shell running in the background so we can
    # return to the caller.
    (
        # Enable fatal error handling inside subshell but do not signal the
        # parent of failures.
        die_on_error
        disable_die_parent
        enable_trace

        # Setup logfile
        elogfile -o=1 -e=1 -r=${logfile_count} -s=${logfile_size} "${logfile}"

        # Info
        einfo "Starting ${name}"

        # Since we are backgrounding this process we don't want to hold onto
        # any open file descriptors our parent may have open. So go ahead and
        # close them now. There's a special case if no logfile was provided
        # where we also need to close STDOUT and STDERR (which normally would
        # have been done by elogfile).
        exec 0</dev/null
        close_fds
        if [[ -z ${logfile} ]]; then
            exec 1>/dev/null 2>/dev/null
        fi

        # Create empty pidfile
        mkdir -p $(dirname ${pidfile})
        touch "${pidfile}"
        local runs=0

        if [[ -n ${cgroup} ]] ; then
            cgroup_create ${cgroup}
            cgroup_move ${cgroup} ${BASHPID}
        fi

        # Check to ensure that we haven't failed running "respawns" times. If
        # we have, then don't run again. Likewise, ensure that the pidfile
        # exists. If it doesn't it likely means that we have been stopped (via
        # daemon_stop) and we really don't want to run again.
        while [[ -e "${pidfile}" && ${runs} -lt ${respawns} ]]; do

            # Increment run counter
            (( runs+=1 ))

            # Execute optional pre_start hook. If this fails for any reason do NOT
            # actually start the daemon.
            $(tryrc ${pre_start})
            [[ ${rc} -eq 0 ]] || { eend 1; break; }

            # Construct a subprocess which bind mounts chroot mount points then executes
            # requested daemon. After the daemon completes automatically unmount chroot.
            (
                die_on_abort
                disable_die_parent
                enable_trace

                # Setup logfile
                elogfile -o=1 -e=1 -t=0 "${logfile}"

                if [[ -n ${chroot} ]]; then
                    export CHROOT=${chroot}
                    chroot_mount
                    trap_add chroot_unmount

                    # If there are additional bindmounts requested mount them as well
                    # with associated traps to ensure they are unmounted.
                    if [[ -n ${bindmounts} ]]; then
                        local mounts=( ${bindmounts} )
                        local mnt
                        for mnt in ${mounts[@]}; do
                            local src="${mnt%%:*}"
                            local dest="${mnt#*:}"
                            [[ -z ${dest} ]] && dest="${src}"

                            if [[ -d ${src} ]]; then
                                mkdir -p ${CHROOT}/${dest}
                            else
                                mkdir -p "$(dirname ${CHROOT}/${dest})"
                                touch ${CHROOT}/${dest}
                            fi

                            ebindmount "${src}" "${CHROOT}/${dest}"
                            trap_add "eunmount ${CHROOT}/${dest}"
                        done
                    fi

                    $netns_cmd_prefix chroot_cmd ${cmdline} || true
                else
                    $netns_cmd_prefix ${cmdline} || true
                fi

            ) &>/dev/null &

            # Get the PID of the process we just created and store into requested pid file.
            local pid=$!
            echo "${pid}" > "${pidfile}"
            eend 0

            # Execute optional post_start hook. Ignore any errors.
            $(tryrc ${post_start})

            # SECONDS is a magic bash variable keeping track of the number of
            # seconds since the shell started, we can modify it without messing
            # with the parent shell (and it will continue from where we leave
            # it).
            SECONDS=0
            wait ${pid} &>/dev/null || true

            # Setup logfile
            elogfile -o=1 -e=1 -t=0 "${logfile}"

            # If we were gracefully shutdown then don't do anything further
            [[ -e "${pidfile}" ]] || { edebug "Gracefully stopped"; exit 0; }

            # Check that we have run for the minimum duration so we can decide
            # if we're going to respawn or not.
            local current_runs=${runs}
            if [[ ${SECONDS} -ge ${respawn_interval} ]]; then
                runs=0
            fi

            # Execute optional post_crash hook and ignore errors.
            $(tryrc ${post_crash})

            # Log specific message
            if [[ ${runs} -ge ${respawns} ]]; then
                eerror "${name} crashed too many times (${runs}/${respawns}). Giving up."
                edebug "$(lval name SECONDS %${optpack})"
                $(tryrc ${post_abort})
            else
                ewarn "${name} crashed (${current_runs}/${respawns}). Will respawn in ${delay} seconds."
                edebug "$(lval name SECONDS %${optpack})"
            fi

            # give daemon_stop a chance to get everything sorted out
            sleep ${delay}
        done

    ) &

    return 0
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
    $(opt_parse \
        ":signal s=TERM        | Signal to use when gracefully stopping the daemon." \
        ":timeout t=5          | Number of seconds to wait after initial signal before sending SIGKILL." \
        ":cgroup_timeout c=300 | Seconds after SIGKILL to wait for processes to actually disappear.  Requires cgroup support." \
        "optpack               | Name of options pack that was returned by daemon_init.")

    $(pack_import ${optpack})

    # Setup logfile
    elogfile -o=1 -e=1 "${logfile}"

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval name signal timeout %${optpack})"

    # If it's not running just return
    daemon_running ${optpack} \
        || { eend 0; edebug "Already stopped"; rm --recursive --force ${pidfile}; return 0; }

    # Execute optional pre_stop hook. Ignore any errors.
    $(tryrc ${pre_stop})

    # If it is remove the pidfile then stop the process with provided signal.
    # NOTE: It's important we remove the pidfile BEFORE we kill the process so that
    # it won't try to respawn!
    local pid=$(cat ${pidfile} 2>/dev/null || true)
    rm --force ${pidfile}
    if [[ -n ${pid} ]]; then
        # kill the process with requested signal
        ekilltree -s=${signal} ${pid}

        # Use eretry to wait up to the maximum timeout for the process to exit.
        # if it fails to exit, then elevate the signal and use SIGKILL.
        $(tryrc eretry -T=${timeout} -d=.1s process_not_running ${pid})
        if [[ ${rc} -ne 0 ]] ; then
            ekilltree -s=SIGKILL ${pid}
        fi

        eend $(process_not_running ${pid})
    else
        eend 0
    fi

    if [[ -n ${cgroup} ]] ; then
        edebug "Waiting for all processes in $(lval cgroup) to die"
        cgroup_kill_and_wait -x="$$ ${BASHPID}" -s=KILL -t=${cgroup_timeout} ${cgroup}
    fi

    # Execute optional post_stop hook. Ignore errors.
    $(tryrc ${post_stop})

    return 0
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
    $(opt_parse \
        "+quiet q | Make the status function produce no output." \
        "optpack  | Name of options pack that was returned by daemon_init.")
    $(pack_import ${optpack})

    local redirect
    [[ ${quiet} -eq 1 ]] && redirect="/dev/null" || redirect="/dev/stderr"

    {
        einfo "${name}"
        edebug "Checking $(lval name %${optpack})"

        # Check pidfile
        [[ -e ${pidfile} ]] || { eend 1; edebug "Not Running (no pidfile)"; return 1; }
        local pid=$(cat ${pidfile} 2>/dev/null || true)
        [[ -n ${pid}     ]] || { eend 1; edebug "Not Running (no pid)"; return 1; }

        # Check if it's running
        process_running ${pid} || { eend 1; edebug "Not Running"; return 1; }

        # OK -- It's running
        edebug "Running $(lval name pid %${optpack})"
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
    $(tryrc daemon_status -q "${@}")
    [[ ${rc} -ne 0 ]]
}

#-----------------------------------------------------------------------------
# SOURCING
#-----------------------------------------------------------------------------
return 0
