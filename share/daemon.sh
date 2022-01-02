#!/bin/bash
#
# Copyright 2012-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2012-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

[[ ${EBASH_OS} == Linux ]] || return 0

__EBASH_DAEMON_RUNDIR="/var/run/ebash-daemon"

#-----------------------------------------------------------------------------------------------------------------------
opt_usage module_daemon <<'END'
The daemon module is used for launching long-running processes asynchronously in the background much like
[daemon](https://man7.org/linux/man-pages/man3/daemon.3.html). All of these daemon functions in this module operate on a
common settings object to make it easier to pass around the details of how to interact with the daemon and the various
options that affect how it is started, stopped, etc.

The underlying data structure for this settings object is a [pack](pack.md). The pack is initialized in `daemon_init`
and must be passed by name to all the other daemon functions. This makes it easy to specify global settings for all of
these daemon functions without having to worry about consistent argument parsing and argument conflicts between the
various daemon_* functions. All of the values set into this pack are available in the caller's various hooks if desired.
If a chroot is provided it is only used inside the body that calls `${cmdline}`. If you need to be in the chroot to
execute a given hook you're responsible for doing that yourself.

The following are the keys used to control daemon functionality:

- **autostart**: Automatically start the configured daemon after a successful daemon_init. This is off by default to
  allow the caller more granular control. Valid values are "true" or "yes" and "false" or "no" (ignoring case).

- **bindmounts**: Optional whitespace separated list of additional paths which whould be bind mounted into the chroot by
  the daemon process during daemon_start. A trap will be setup so that the bind mounts are automatically unmounted when
  the process exits. The syntax for these bind mounts allow mounting them into alternative paths inside the chroot using
  a colon to delimit the source path outside the chroot and the desired mount point inside the chroot. (e.g.
  `/var/log/kern.log:/var/log/host_kern.log`)

- **cfgfile**: This is a file that ebash will store the pack configuration information about the daemon. By default this
  is `${__EBASH_DAEMON_RUNDIR}`. This allows external integration into other parts of ebash such as the docker systemctl
  wrapper which can be used to start/stop and query the status of daemons. Set this to an empty string if you want to
  disable this.

- **cgroup**: Optional cgroup to run the daemon in. If the cgroup does not exist it will be created for you. The daemon
  assumes ownership of ALL processes in that cgroup and will kill them at shutdown time. (So give it its own cgroup).
  See cgroups.sh for more information.

- **chroot**: Optional CHROOT to run the daemon in. chroot_cmd will be used to execute the provided command line but all
  other hooks will be performed outside of the chroot. Though the CHROOT variable will be availble in the hooks if
  needed.

- **cmdline**: The command line to be run as a daemon. This includes the executable as well as any of its arguments.

- **delay**: The delay to wait, in sleep(1) syntax, before attempting to restart the daemon when it exits. This should
  never be <1s otherwise race conditions in startup and shutdown are possible. Defaults to 1s.

- **enabled**: Control whether a daemon is "enabled" or not. Do not confuse enabling a daemon with starting a daemon.
  These are orthogonal concepts. Enabling a daemon exists for compatibility with our systemd wrappers inside of docker
  where we have a thin init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being
  auto started by the init daemon then you would disable it. Valid values are "true" or "yes" and "false" or "no"
  (ignoring case).

- **logfile**: Optional logfile to send all stdout and stderr to for the daemon. Since it generally doesn't make sense
  for the stdout/stderr of the daemon to spew into the caller's stdout/stderr, these will default to /dev/null if not
  otherwise specified.

- **logfile_count**: Maximum number of logfiles to keep (defaults to 5). See elogfile and elogrotate for more details.

- **logfile_size**: Maximum logfile size before logfiles should be rotated. This defaults to zero such that if you
  provide any logfile it will be rotated automatially. See elogfile and elogrotate for more details.

- **name**: The name of the daemon, for readability purposes. By default this will use the name of the configuration
  pack.

- **pidfile**: Path to the pidfile for the daemon. By default this is the name of the configuration pack and is stored
  in `${__EBASH_DAEMON_RUNDIR}/${name}.pid`

- **pre_start**: Optional hook to be executed before starting the daemon. Must be a single command to be executed. If
  more complexity is required use a function. If this hook fails, the daemon will NOT be started or respawned.

- **pre_stop**: Optional hook to be executed before stopping the daemon. Must be a single command to be executed. If
  more complexity is required use a function. Any errors from this hook are ignored.

- **post_mount**: Optional hook to be executed after bind mounts have been created but before starting the daemon. Must
  be a single command to be executed. If more complexity is required use a function. This hook is invoked regardless of
  whether this daemon has bind mounts. Any errors from this hook are ignored

- **post_stop**: Optional hook to be exected after stopping the daemon. Must be a single command to be executed. If more
  complexity is required use a function. Any errors from this hook are ignored.

- **post_crash**: Optional hook to be executed after the daemon stops abnormally (i.e not through daemon_stop). Errors
  from this hook are ignored.

- **post_abort**: Optional hook to be called after the daemon aborts due to crashing too many times. Errors from this
  hook are ignored.

- **respawns**: The maximum number of times to respawn the daemon command before just giving up. Defaults to 10.

- **respawn_interval**: Amount of seconds the process must stay up for it to be considered a successful start. This is
  used in conjunction with respawn similar to upstart/systemd. If the process is respawned more than ${respawns} times
  within ${respawn_interval} seconds, the process will no longer be respawned.

- **netns_name**: Network namespce to run the daemon in. The namespace must be created and properly configured before
  use. If you use this, you need to source netns.sh from ebash prior to calling daemon_start
END
#-----------------------------------------------------------------------------------------------------------------------

opt_usage daemon_pack_save <<'END'
`daemon_pack_save` is used to save the optional pack for a daemon to an on-disk configuration file which is stored in
the cfgfile field of the option pack. This allows the pack to be reused by many different ebash daemon functions more
implicitly as each function can load the configuration from disk.
END
daemon_pack_save()
{
    $(opt_parse optpack)
    edebug "$(lval %${optpack})"

    local cfgfile
    cfgfile="$(pack_get ${optpack} "cfgfile")"
    if [[ -n "${cfgfile}" ]]; then
        edebug "Creating $(lval cfgfile)"
        mkdir -p "$(dirname "${cfgfile}")"
        pack_save "${optpack}" "${cfgfile}"
    fi
}

opt_usage daemon_init <<'END'
`daemon_init` is used to initialize the options pack that all of the various daemon_* functions will use. This makes it
easy to specify global settings for all of these daemon functions without having to worry about consistent argument
parsing and argument conflicts between the various daemon_* functions. All of the values set into this pack are
available in the caller's various hooks if desired. If a chroot is provided it is only used inside the body that calls
`${cmdline}`. If you need to be in the chroot to execute a given hook you're responsible for doing that yourself.
END
daemon_init()
{
    $(opt_parse optpack)

    # Load defaults into the pack first then add in any additional provided settings Since the last key=val added to the
    # pack will always override prior values this allows caller to override the defaults.
    pack_set ${optpack}               \
        autostart="false"             \
        bindmounts=                   \
        cfgfile="${__EBASH_DAEMON_RUNDIR}/${optpack}" \
        cgroup=                       \
        chroot=                       \
        delay=1                       \
        enabled="true"                \
        logfile=                      \
        logfile_count=0               \
        logfile_size=0                \
        name=${optpack}               \
        netns_name=                   \
        pidfile="${__EBASH_DAEMON_RUNDIR}/${optpack}.pid" \
        post_abort=                   \
        post_crash=                   \
        post_mount=                   \
        post_stop=                    \
        pre_start=                    \
        pre_stop=                     \
        respawn_interval=15           \
        respawns=20                   \
        "${@}"

    edebug "$(lval %${optpack})"

    daemon_pack_save "${optpack}"

    local autostart
    autostart=$(pack_get ${optpack} "autostart")
    if [[ "${autostart,,}" == @(yes|true) ]]; then
        daemon_start ${optpack}
    fi

    return 0
}

opt_usage daemon_start <<'END'
daemon_start will daemonize the provided command and its arguments as a pseudo-daemon and automatically respawn it on
failure. We don't use the core operating system's default daemon system, as that is platform dependent and lacks the
portability we need to daemonize things on any arbitrary system.

For options which control daemon_start functionality please see daemon_init.
END
daemon_start()
{
    # Pull in our argument pack then import all of its settings for use.
    $(opt_parse optpack)
    $(pack_import ${optpack})

    # Don't restart the daemon if it is already running.
    if daemon_running ${optpack}; then
        local pid
        pid=$(cat ${pidfile} 2>/dev/null || true)
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

    # Split this off into a separate sub-shell running in the background so we can return to the caller.
    (
        # Enable fatal error handling inside subshell but do not signal the parent of failures.
        die_on_error
        disable_die_parent
        enable_trace

        # Setup logfile
        if [[ -n "${logfile}" ]] ; then
            elogfile --stdout --stderr --no-tail --rotate_count ${logfile_count} --rotate_size ${logfile_size} "${logfile}"
        fi

        # Info
        einfo "Starting ${name}"

        # Since we are backgrounding this process we don't want to hold onto any open file descriptors our parent may
        # have open. So go ahead and close them now. There's a special case if no logfile was provided where we also
        # need to close STDOUT and STDERR (which normally would have been done by elogfile).
        exec 0</dev/null
        close_fds

        # Create empty pidfile
        mkdir -p $(dirname ${pidfile})
        touch "${pidfile}"
        local runs=0

        if [[ -n ${cgroup} ]] ; then
            cgroup_create ${cgroup}
            cgroup_move ${cgroup} ${BASHPID}
        fi

        # Check to ensure that we haven't failed running "respawns" times. If we have, then don't run again. Likewise,
        # ensure that the pidfile exists. If it doesn't it likely means that we have been stopped (via daemon_stop) and
        # we really don't want to run again.
        while [[ -e "${pidfile}" && ${runs} -lt ${respawns} ]]; do

            # Increment run counter
            (( runs+=1 ))

            # Execute optional pre_start hook. If this fails for any reason do NOT actually start the daemon.
            $(tryrc ${pre_start})
            [[ ${rc} -eq 0 ]] || { eend 1; break; }

            # Construct a subprocess which bind mounts chroot mount points then executes requested daemon. After the
            # daemon completes automatically unmount chroot.
            (
                die_on_abort
                disable_die_parent
                enable_trace

                # Normal shutdown for the daemon will cause SIGTERM to this process. That's great, we'll let it shut us
                # down, but without printing a stack trace because this is a normal situation.
                trap - SIGTERM

                if [[ -n ${chroot} ]]; then
                    export CHROOT=${chroot}
                    chroot_mount
                    trap_add chroot_unmount

                    # If there are additional bindmounts requested mount them as well with associated traps to ensure
                    # they are unmounted.
                    if [[ -n ${bindmounts} ]]; then
                        local mounts=( ${bindmounts} )
                        local mnt
                        for mnt in "${mounts[@]}"; do
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

                    # Execute optional post_mount hook. Ignore any errors.
                    $(tryrc ${post_mount})

                    ${netns_cmd_prefix} chroot_cmd ${cmdline} || true
                else

                    # Execute optional post_mount hook. Ignore any errors.
                    $(tryrc ${post_mount})
                    ${netns_cmd_prefix} ${cmdline} || true
                fi

            ) &

            # Get the PID of the process we just created and store into requested pid file.
            local pid=$!
            echo "${pid}" > "${pidfile}"
            eend 0

            # SECONDS is a magic bash variable keeping track of the number of seconds since the shell started, we can
            # modify it without messing with the parent shell (and it will continue from where we leave it).
            SECONDS=0
            wait ${pid} &>/dev/null || true

            # If we were gracefully shutdown then don't do anything further
            if [[ ! -e "${pidfile}" ]]; then
                edebug "Gracefully stopped"
                exit 0
            fi

            # Check that we have run for the minimum duration so we can decide if we're going to respawn or not.
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

opt_usage daemon_stop <<'END'
daemon_stop will find a command currently being run as a pseudo-daemon, terminate it with the provided signal, and clean
up afterwards.

For options which control daemon_start functionality please see daemon_init.
END
daemon_stop()
{
    # Pull in our argument pack then import all of its settings for use.
    $(opt_parse \
        ":signal s=TERM        | Signal to use when gracefully stopping the daemon."                                   \
        ":timeout t=5          | Number of seconds to wait after initial signal before sending SIGKILL."               \
        ":cgroup_timeout c=300 | Seconds after SIGKILL to wait for processes to actually disappear. Requires cgroup
                                 support. If you specify a c=<some number of seconds>, we'll give up (and return an
                                 error) after that many seconds have elapsed. By default, this is 300 seconds. If you
                                 specify 0, this will wait forever."                                                   \
        "optpack               | Name of options pack that was returned by daemon_init.")

    $(pack_import ${optpack})

    # Setup logfile
    if [[ -n "${logfile}" ]] ; then
        elogfile -o=1 -e=1 "${logfile}"
    fi

    # Info
    einfo "Stopping ${name}"
    edebug "Stopping $(lval name signal timeout %${optpack})"

    # If it's not running just return
    if daemon_not_running ${optpack}; then
        eend 0
        edebug "Already stopped"
        rm --recursive --force ${pidfile}
        return 0
    fi

    # Execute optional pre_stop hook. Ignore any errors.
    $(tryrc ${pre_stop})

    # If it is remove the pidfile then stop the process with provided signal. NOTE: It's important we remove the
    # pidfile BEFORE we kill the process so that it won't try to respawn!
    local pid
    pid=$(cat ${pidfile} 2>/dev/null || true)
    rm --force ${pidfile}
    if [[ -n ${pid} ]]; then
        # kill the process with requested signal
        ekilltree -s=${signal} ${pid}

        # Use eretry to wait up to the maximum timeout for the process to exit. If it fails to exit, then elevate the
        # signal and use SIGKILL.
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

opt_usage daemon_status <<'END'
Retrieve the status of a daemon.

For options which control daemon_start functionality please see daemon_init.
END
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
        einfo "Checking ${name}"
        edebug "Checking $(lval name %${optpack})"

        # No Pidfile
        if [[ ! -e ${pidfile} ]]; then
            eend 1
            edebug "Not Running (no pidfile)"
            return 1
        fi

        # Pidfile, but not running
        local pid
        pid=$(cat ${pidfile} 2>/dev/null || true)
        if [[ -z ${pid} ]]; then
            eend 1
            edebug "Not Running (no pid)"
            return 1
        fi

        # Check if it's running
        if process_not_running ${pid}; then
            eend 1
            edebug "Not Running"
            return 1
        fi

        # OK -- It's running
        edebug "Running $(lval name pid %${optpack})"
        eend 0

    } &>${redirect}

    return 0
}

opt_usage daemon_restart <<'END'
daemon_restart is a wrapper around daemon_stop followed by daemon_start. It is not a failure for the deamon to not be
running and then call daemon_restart.
END
daemon_restart()
{
    # Pull in our argument pack then import all of its settings for use.
    $(opt_parse \
        ":signal s=TERM        | Signal to use when gracefully stopping the daemon."                                   \
        ":timeout t=5          | Number of seconds to wait after initial signal before sending SIGKILL."               \
        ":cgroup_timeout c=300 | Seconds after SIGKILL to wait for processes to actually disappear. Requires cgroup
                                 support. If you specify a c=<some number of seconds>, we'll give up (and return an
                                 error) after that many seconds have elapsed. By default, this is 300 seconds. If you
                                 specify 0, this will wait forever."                                                   \
        "optpack               | Name of options pack that was returned by daemon_init.")

    opt_forward daemon_stop signal timeout cgroup_timeout -- ${optpack}
    daemon_start ${optpack}
}

opt_usage daemon_running <<'END'
Check if the daemon is running. This is just a convenience wrapper around "daemon_status --quiet". This is a little more
convenient to use in scripts where you only care if it's running and don't want to have to suppress all the output from
daemon_status.
END
daemon_running()
{
    daemon_status --quiet "${@}"
}

opt_usage daemon_not_running <<'END'
Check if the daemon is not running
END
daemon_not_running()
{
    $(tryrc daemon_status -q "${@}")
    [[ ${rc} -ne 0 ]]
}

opt_usage daemon_enable <<'END'
daemon_enable is used to enable a daemon. Do not confuse enabling a daemon with starting a daemon. These are orthogonal
concepts. Enabling a daemon exists for compatibility with our systemd wrappers inside of docker where we have a thin
init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto started by the init
daemon then you would disable it.
END
daemon_enable()
{
    $(opt_parse optpack)

    pack_set ${optpack} enabled="true"
    edebug "$(lval %${optpack})"
    daemon_pack_save "${optpack}"
}

opt_usage daemon_disable <<'END'
daemon_disable is used to disable a daemon. Do not confuse disabling a daemon with stopping a daemon. These are
orthogonal concepts. Disabling a daemon exists for compatibility with our systemd wrappers inside of docker where we
have a thin init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto started
by the init daemon then you would disable it.
END
daemon_disable()
{
    $(opt_parse optpack)

    pack_set ${optpack} enabled="false"
    edebug "$(lval %${optpack})"
    daemon_pack_save "${optpack}"
}

opt_usage daemon_enabled <<'END'
daemon_enabled is used to check if a daemon is enabled or not. Do not confuse enabling a daemon with starting a daemon.
These are orthogonal concepts. Enabling a daemon exists for compatibility with our systemd wrappers inside of docker
where we have a thin init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto
started by the init daemon then you would disable it.
END
daemon_enabled()
{
    $(opt_parse optpack)
    $(pack_import ${optpack})

    [[ "${enabled,,}" == @(yes|true) ]]
}
