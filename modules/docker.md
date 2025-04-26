# Module docker


## func docker_build

`docker_build` is used to intelligently build a docker image from a Dockerfile using an external cache docker
registry/repo which may be the same or different from the production registry/repo. For example, we typically have a
dedicated registry/repo for CI/CD images which are treated only as a cache and can be prunned or blown away entirely as
needed. We have a separate registry/repo for our official released builds which we want to keep uncluttered.

The main functionality added by docker_build is to avoid building redudant, identical docker images. The most common use
case here is lots of git branches all trying to build and tag docker images which are essentially identical. Even with
docker's built-in layer caching mechanism, "docker build" always hits the cache and does a new build even on 100% cache
hits. Granted the build will be _fast_, but it's still unecessary if we've already built it with identical content but a
different tag. Moreover, vanilla "docker build" command is not distributed. Every developer is forced to do a build even
if another developer has already built and published. Ebash's "docker_build" addresses this problem using the cach repo.

The algorithm we employ is as follows:

- Look for the image locally
- Try to download the underlying content-based SHA image from docker cache repository
- Build the docker image from scratch

This entire algorithm is built on a simple idea of essentially computing our own simplistic sha256 dependency SHA which
captures the content of the provided Dockerfile as well as any files which are dynamically copied or added via COPY/ADD
directives in the Dockerfile as well as any build arguements. We then simply use that dynamically generated content
based tag to easily be able to look for the image in the cache repository. For more details see docker_depends_sha.

### Overlay Modules

docker_build supports the concept of overlay modules which facilitates copying files into the resulting docker image
that we build. The purpose of this is to provide dockerized versions of things that would otherwise not work properly
inside docker. The best example of this is systemd. Systemd binaries, such as systemctl and journalctl, do not function
properly inside docker because there is no init daemon inside docker containers. To solve this problem, ebash provides a
set of replacements for systemd binaries that simulate their intended functionality. These are generally NOT fully
functional replacements but simple, stripped down replacements that get the job done.

The overlay files are automatically accounted for with the built-in dependency SHA and caching mechanism used by
docker_build.

There are several built-in overlay modules provided by ebash that you can enable via --overlay=<module>. This is an
accumulator so you can pass it in multiple times to enable multiple overlay modules.

- **systemd**

  This provides several critical binary replacements to provide seamless systemd-like functionality:

  - **/usr/local/bin/systemctl**: manage multiple ebash controlled daemons. This supports `start`, `stop`, `status`,
    `restart` actions on each daemon.
  - **/usr/local/bin/timedatectl**: simulate systemd timedatectl functionality. This supports being called with no
    arguments and it will output something similar to the real timedatectl. It also supports being called with
    `set-timezone ZONE`.
  - **/usr/local/bin/journalctl**: This does not implement the full journalctl functionality but instead acts as a
    lightweight wrapper around rsyslog logger. By default if you call this with no arguments it will simply cat
    `/var/log/messages` and pass them into your pager. If you pass in `-f` or `--follow` it will tail the log file.

- **rsyslog**

   This is *NOT* a full replacement for rsyslog. Instead it simply provides a custom `/etc/rsylog.conf` file which
   allows rsyslog to function properly inside docker. You also need to __install__ rsyslog in your container and
   must also start it up as a daemon (probably using ebash controlled init script).

- **selinux**

   This is *NOT* a full replacement for selinux. Instead it simply provides a custom `/etc/selinux/config` file which
   completely disables selinux entirely as it doesn't work inside docker.

Finally, you can install your own custom overlay files via `--overlay-tree=<path>`. The entire tree of the provided path
will be copied into the root of the created container. For example, if you had `overlay/usr/local/bin/foo` and you
called `docker_build --overlay-tree overlay` then inside the container you will have `/usr/local/bin/foo`.

If you want to push any tags you need to provide `--username` and `--password` arguments or have `DOCKER_USERNAME` and
`DOCKER_PASSWORD` environment variables set.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --build-arg (&)
         Build arguments to pass into lower level docker build --build-arg.

   --cache
         Use local docker cache when building docker image.

   --cache-from <value>
         Images to consider as cache sources. Passthrough into docker build.

   --file <value>
         The docker file to use. Defaults to Dockerfile.

   --ibuild-arg (&)
         Build arguments that should be interpolated inplace instead of passing into the lower
         level docker build.

   --name <non-empty value> (*)
         Name of docker image to create. This will also be used as the cache registry/repository
         for cached remote images.

   --overlay (&)
         Builtin ebash overlay module to install into the image.

   --overlay-tree <value>
         Tree of additional local files to copy into the resulting image.

   --password <value>
         Password for registry login. Defaults to DOCKER_PASSWORD env variable.

   --pretend
         Do not actually build the docker image. Return 0 if image already exists and 1 if the
         image does not exist and a build is required.

   --pull
         Pull the image and all tags from the remote registry/repo.

   --push
         Push the image and all tags to remote registry/repo.

   --registry <value>
         Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable which itself
         defaults to https://index.docker.io/v1/ if not set.

   --shafunc <value>
         SHA function to use. Default to sha256.

   --tag (&)
         Tags to assign to the image of the form registry/repo:tag. This allows you to actually
         tag and push to multiple repositories in one operation.

   --username <value>
         Username for registry login. Defaults to DOCKER_USERNAME env variable.

   --workdir <value>
         Temporary work directory to save output files to.

```

## func docker_depends_sha

`docker_depends_sha` is used to compute the dependency SHA for a dockerfile as well as any additional files it copies
into the resulting docker image (including overlay modules and overlay_tree files) and also and build arguments used to
create it. This is used by docker_build to avoid building docker images when none of the dependencies have changed.

This function will create some output state files underneath ${workdir}/docker/$(basename ${name}) that are used
internally by docker_build but also useful externally.

- **build.log**  : Output from the docker build process
- **dockerfile** : Contains docker file with overlay information added by ebash and any ibuild variables interpolated.
- **history**    : Contains output of 'docker history'
- **image**      : The full image name including name:sha
- **inspect**    : Contains output of 'docker inspect'
- **options**    : Options passed into docker_build
- **sha**        : Contains full content based sha of the dependencies to create the docker image
- **sha.detail** : Contains details of all the dependencies that affect the image along with their respective SHAs.
- **sha.func**   : Contains the SHA function used (e.g. sha256)
- **sha.short**  : Contains first 12 characters of the full SHA of the dependencies of the image

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --file <value>
         The docker file to use. Defaults to Dockerfile.

   --ibuild-arg (&)
         Build arguments to pass into lower level docker build --build-arg.

   --name <non-empty value> (*)
         Name of docker image to create. This will also be used as the cache registry/repository
         for cached remote images.

   --overlay (&)
         Builtin ebash overlay module to install into the image.

   --overlay-tree <value>
         Tree of additional local files to copy into the resulting image.

   --shafunc <value>
         SHA function to use. Default to sha256.

   --workdir <value>
         Temporary work directory to save output files to.

```

## func docker_export

`docker_export` is a wrapper around `docker export` to make it more seamless to convert a provided docker image to
various archive formats. This code intentionally does not use ebash archive module as that is too heavy weight for our
needs and also requires the caller to be root to do the bind mounting.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --type, -t <value>
         Override automatic type detection and use explicit archive type.


ARGUMENTS

   tag
         Docker tag to to export in the form of name:tag.

   output
         Output archive to create.

```

## func docker_image_exists

`docker_image_exists` is a simple function to easily check if a remote docker image exists. This makes use of an
experimental feature in docker cli to be able to inspect a remote manifest without having to first pull it.

```Groff
ARGUMENTS

   tag
         Docker tag to check for the existance of in the form of name:tag.

```

## func docker_login

`docker_login` is an intelligent wrapper around vanilla `docker login` which integrates nicely with ebash. The most
important functionality it provides is to seamlessly reuse existing docker login sessions in ~/.docker/config.json.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --password <value>
         Password for registry login. Defaults to DOCKER_PASSWORD env variable.

   --registry <non-empty value> (*)
         Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable which itself
         defaults to https://index.docker.io/v1/ if not set.

   --reuse
         Reuse an existing authentication session if one already exists.

   --username <value>
         Username for registry login. Defaults to DOCKER_USERNAME env variable.

```

## func docker_pull

`docker_pull` is an intelligent wrapper around vanilla `docker pull` which integrates more nicely with ebash. In
addition to the normal additional error checking and hardening the ebash variety brings, this also provide the following
functionality:

- Seamlessly login to docker registry before pushing as-needed.
- Accepts an array of tags to pull and pulls them all.
- Fallback to local build if remote pull fails.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --cache-from <value>
         Images to consider as cache sources. Passthrough into docker build.

   --fallback
         If pull fails, build locally.

   --file <value>
         The docker file to use. Defaults to Dockerfile.

   --image <value>
         Base image to look for in the event we are unable to locate the requested tags
         locally. This saves us from having to rebuild all the images if we can simply tag
         them instead.

   --password <value>
         Password for registry login. Defaults to DOCKER_PASSWORD env variable.

   --registry <value>
         Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable which itself
         defaults to https://index.docker.io/v1/ if not set.

   --username <value>
         Username for registry login. Defaults to DOCKER_USERNAME env variable.


ARGUMENTS

   tags
         List of tags to pull from the remote registry/repo.
```

## func docker_push

`docker_push` is an intelligent wrapper around vanilla `docker push` which integrates more nicely with ebash. In
addition to the normal additional error checking and hardening the ebash variety brings, this also provide the following
functionality:

- Seamlessly login to docker registry before pushing as-needed.
- Accepts an array of tags to push and pushes them all.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --password <value>
         Password for registry login. Defaults to DOCKER_PASSWORD env variable.

   --registry <value>
         Remote docker registry for login. Defaults to DOCKER_REGISTRY env variable which itself
         defaults to https://index.docker.io/v1/ if not set.

   --username <value>
         Username for registry login. Defaults to DOCKER_USERNAME env variable.


ARGUMENTS

   tags
         List of tags to push to remote registry/repo.
```

## func docker_run

`docker_run` is an intelligent wrapper around vanilla `docker run` which integrates nicely with ebash. In addition to
the normal additional error checking and hardening the ebash variety brings, this version provides the following super
useful features:

- Accept a list of environment variables which should be exported into the underlying docker run command. Each of these
  variables will be expanded in-place by ebash using `expand_vars`. As such the variables can be a simple list of env
  variables to export as in `FOO BAR ZAP` or they can point to other variables as in `FOO=PWD BAR ZAP` or they can
  point to string literals as in `FOO=/home/marshall BAR=1 ZAP=blah`. Each of these will be expanded into a formatted
  option to docker of the form `--env FOO=VALUE`.
- Enable seamless nested docker-in-docker support by bind-mounting the docker socket into the the container.
- Create ephemeral docker volumes and copy a specified local path into the docker volume and attach that volume to the
  running docker container. This is useful for running with a remote docker context or DOCKER_HOST which points to an
  external docker server.
- Automatically determine what value to use for --interactive.
- Optionally setup SSH Port Forwarding when used with a remote docker context or DOCKER_HOST. If the context is not set
  to a remote SSH host, then this option will have no effect.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --copy-from-volume (&)
         Copy the specified path out of a volume attached to the docker container before it is
         removed. This is useful to copy artifacts out from a test container. The syntax for
         this is name:docker_path:local_path

   --copy-from-volume-delete (&)
         After copying all volumes back to the local site, delete any paths in this list. This
         is because docker cp doesn't support an exclusion mechanism.

   --copy-to-volume (&)
         Copy the specified path into a volume which is attached to the docker run instance. This
         is useful when running with a remote docker context or DOCKER_HOST where a simple bind
         mount does not work. This is also safe to use when running against a local docker host
         so should be preferred. The syntax for this is name:local_path:docker_path

   --envlist <value>
         List of environment variables to pass into lowever level docker run. These will be
         sorted before passing them into docker for better testability and consistency.

   --interactive <value>
         This can be 'yes' or 'no' or 'auto' to automatically determine if we are interactive
         by looking at we're run from an interactive shell or not.

   --nested
         Enable nested docker-in-docker.

   --ssh-port-forward (&)
         Setup SSH Port Forwarding for use with remote docker context or remote DOCKER_HOST. If
         the context is not set to a remote SSH host, then this option has no effect.

```

## func docker_tag

`docker_tag` is an intelligent wrapper around vanilla `docker tag` which integrates more nicely with ebash. In
addition to the normal additional error checking and hardening the ebash variety brings, this version is variadic and
will apply a list of tags to a given base image.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --image <non-empty value> (*)
         Base image to look for in the event we are unable to locate the requested tags
         locally. This saves us from having to rebuild all the images if we can simply tag
         them instead.


ARGUMENTS

   tags
         List of tags to apply to the base image.
```

## func running_in_container

Check if we are running inside a container or not.

## func running_in_docker

Check if we are running inside docker or not.
