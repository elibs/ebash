#
# Copyright 2011-2021, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#----------------------------------------------------------------------------------------------------------------------
#
# Settings
#
#----------------------------------------------------------------------------------------------------------------------

# Runtime option flags
# NOTE: The $(or ...) idiom allows these options to be case-insensitive to make them easier to pass at the command-line.
BREAK   ?= $(or ${break},0)
EDEBUG  ?= $(or $(or ${edebug},${debug},))
EXCLUDE ?= $(or ${exclude},)
FILTER  ?= $(or ${filter},)
REPEAT  ?= $(or ${repeat},0)
V       ?= $(or $v,0)

.SILENT:

#----------------------------------------------------------------------------------------------------------------------
#
# Targets
#
#----------------------------------------------------------------------------------------------------------------------

.PHONY: ctags
ctags: tests/unit/*.sh tests/unit/*.etest share/*.sh bin/*
	ctags -f .tags . $^

.PHONY: clean
clean:
	git clean -fX

.PHONY: clobber
clobber: clean
	sudo bin/ebash rm -frv --one-file-system .work tests/self/output
	sudo bin/ebash git clean -f
	sudo bin/ebash git clean -fd
	sudo bin/ebash git clean -fX

.PHONY: lint
lint:
	bin/bashlint

.PHONY: selftest
selftest:
	bin/selftest

.PHONY: test
test:
	bin/etest \
		--break=${BREAK}        \
		--debug="${EDEBUG}"     \
		--exclude="${EXCLUDE}"  \
		--filter="${FILTER}"    \
		--repeat=${REPEAT}      \
		--verbose=${V}

.PHONY: doc
doc:
	bin/edoc

#----------------------------------------------------------------------------------------------------------------------
#
# Docker Tests
#
#----------------------------------------------------------------------------------------------------------------------

# Template for running tests inside a Linux distro container
DRUN = docker run      \
       --init          \
       --tty           \
       --interactive   \
       --network host  \
       --privileged    \
       --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
       --mount type=bind,source=${PWD},target=/ebash \
       --workdir /ebash \
       --rm

define DOCKER_TEST_TEMPLATE

.PHONY: dselftest-$1
dselftest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "EDEBUG=${EDEBUG} install/all && bin/selftest"

.PHONY: dtest-$1
dtest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "EDEBUG=${EDEBUG} install/all && \
        bin/etest \
            --break                    \
            --debug="${EDEBUG}"        \
            --exclude="${EXCLUDE}"     \
            --filter="${FILTER}"       \
            --log-dir=.work            \
            --repeat=${REPEAT}         \
            --verbose=${V}             \
            --work-dir=.work/output"

.PHONY: dshell-$1
dshell-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "EDEBUG=${EDEBUG} install/all && /bin/bash"

endef

DISTROS =           \
	alpine:3.13     \
	alpine:3.12     \
	archlinux       \
	centos:8        \
	centos:7        \
	debian:10       \
	debian:9        \
	fedora:33       \
	fedora:32       \
	gentoo/stage3   \
	ubuntu:20.04    \
	ubuntu:18.04    \

$(foreach t,${DISTROS},$(eval $(call DOCKER_TEST_TEMPLATE,$(subst :,-,$t),${t})))

PHONY: dtest
dtest:	    $(foreach d, $(subst :,-,${DISTROS}), dtest-${d})
dselftest:  $(foreach d, $(subst :,-,${DISTROS}), dselftest-${d})
