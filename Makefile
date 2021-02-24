#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#----------------------------------------------------------------------------------------------------------------------
#
# TARGETS
#
#----------------------------------------------------------------------------------------------------------------------

.SILENT:

V?=0
BREAK?=0
REPEAT?=0

.PHONY: ctags clean clobber

ctags: unittest/*.sh unittest/*.etest share/*.sh bin/*
	ctags -f .tags . $^

clean:
	git clean -fX

clobber: clean
	sudo bin/ebash rm -frv --one-file-system .work

lint:
	bin/bashlint

test:
	bin/etest \
		--work_dir=.work/output \
		--log_dir=.work         \
		--verbose=${V}          \
		--filter=${FILTER}      \
		--exclude=${EXCLUDE}    \
		--repeat=${REPEAT}      \
		--break=${BREAK}

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
       --privileged    \
       --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
       --mount type=bind,source=${PWD},target=/ebash \
       --workdir /ebash \
       --rm
define DOCKER_TEST_TEMPLATE

.PHONY: dselftest-$1
dselftest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && bin/selftest"

.PHONY: dtest-$1
dtest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && bin/etest --break --verbose=${V} --filter=${FILTER} --exclude=${EXCLUDE} --repeat=${REPEAT} --break=${BREAK}"

.PHONY: dshell-$1
dshell-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && /bin/bash"

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
