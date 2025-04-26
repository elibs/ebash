# Module daemon

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

## func daemon_disable

daemon_disable is used to disable a daemon. Do not confuse disabling a daemon with stopping a daemon. These are
orthogonal concepts. Disabling a daemon exists for compatibility with our systemd wrappers inside of docker where we
have a thin init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto started
by the init daemon then you would disable it.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_enable

daemon_enable is used to enable a daemon. Do not confuse enabling a daemon with starting a daemon. These are orthogonal
concepts. Enabling a daemon exists for compatibility with our systemd wrappers inside of docker where we have a thin
init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto started by the init
daemon then you would disable it.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_enabled

daemon_enabled is used to check if a daemon is enabled or not. Do not confuse enabling a daemon with starting a daemon.
These are orthogonal concepts. Enabling a daemon exists for compatibility with our systemd wrappers inside of docker
where we have a thin init daemon which auto starts all enabled daemons. If you want to prevent a daemon from being auto
started by the init daemon then you would disable it.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_init

`daemon_init` is used to initialize the options pack that all of the various daemon_* functions will use. This makes it
easy to specify global settings for all of these daemon functions without having to worry about consistent argument
parsing and argument conflicts between the various daemon_* functions. All of the values set into this pack are
available in the caller's various hooks if desired. If a chroot is provided it is only used inside the body that calls
`${cmdline}`. If you need to be in the chroot to execute a given hook you're responsible for doing that yourself.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_not_running

Check if the daemon is not running

## func daemon_pack_save

`daemon_pack_save` is used to save the optional pack for a daemon to an on-disk configuration file which is stored in
the cfgfile field of the option pack. This allows the pack to be reused by many different ebash daemon functions more
implicitly as each function can load the configuration from disk.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_restart

daemon_restart is a wrapper around daemon_stop followed by daemon_start. It is not a failure for the deamon to not be
running and then call daemon_restart.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --cgroup-timeout, -c <value>
         Seconds after SIGKILL to wait for processes to actually disappear. Requires cgroup
         support. If you specify a c=<some number of seconds>, we'll give up (and return an error)
         after that many seconds have elapsed. By default, this is 300 seconds. If you specify 0,
         this will wait forever.

   --signal, -s <value>
         Signal to use when gracefully stopping the daemon.

   --timeout, -t <value>
         Number of seconds to wait after initial signal before sending SIGKILL.


ARGUMENTS

   optpack
         Name of options pack that was returned by daemon_init.

```

## func daemon_running

Check if the daemon is running. This is just a convenience wrapper around "daemon_status --quiet". This is a little more
convenient to use in scripts where you only care if it's running and don't want to have to suppress all the output from
daemon_status.

## func daemon_start

daemon_start will daemonize the provided command and its arguments as a pseudo-daemon and automatically respawn it on
failure. We don't use the core operating system's default daemon system, as that is platform dependent and lacks the
portability we need to daemonize things on any arbitrary system.

For options which control daemon_start functionality please see daemon_init.

```Groff
ARGUMENTS

   optpack
        optpack

```

## func daemon_status

Retrieve the status of a daemon.

For options which control daemon_start functionality please see daemon_init.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --quiet, -q
         Make the status function produce no output.


ARGUMENTS

   optpack
         Name of options pack that was returned by daemon_init.

```

## func daemon_stop

daemon_stop will find a command currently being run as a pseudo-daemon, terminate it with the provided signal, and clean
up afterwards.

For options which control daemon_start functionality please see daemon_init.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --cgroup-timeout, -c <value>
         Seconds after SIGKILL to wait for processes to actually disappear. Requires cgroup
         support. If you specify a c=<some number of seconds>, we'll give up (and return an error)
         after that many seconds have elapsed. By default, this is 300 seconds. If you specify 0,
         this will wait forever.

   --signal, -s <value>
         Signal to use when gracefully stopping the daemon.

   --timeout, -t <value>
         Number of seconds to wait after initial signal before sending SIGKILL.


ARGUMENTS

   optpack
         Name of options pack that was returned by daemon_init.

```
