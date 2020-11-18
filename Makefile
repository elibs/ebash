#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

#----------------------------------------------------------------------------------------------------------------------
#
# VERBOSITY
#
#----------------------------------------------------------------------------------------------------------------------

# Levels of V can increase verbosity of 'make'. This can be made your global default by setting MAKEVERBOSE in your shell.
#
# The meanings of the various verbosity levels are:
#
# V=0: Don't show gcc compilation commands and instead use terse kbuild style output
# V=1: Show all make commands as they are invoked
# V=2: Basic Makefile debugging information (--debug=b). Sets EDEBUG=1.
# V=3: More verbose make debugging (--debug=bv).
# V=4: Show implicit Makefile rules (--debug=bvi)
# V=5: Show details on invocations of all commands (--debug=bvij).
# V=6: Show debugging information while remaking makefiles (--debug=bvijm).
MAKEVERBOSE ?= 0
V ?= ${MAKEVERBOSE}

# Helper template for setting up debugging of the Makefile itself by appending to MAKEFLAGS with --debug=$1 (e.g.
# --debug=b -- see 'man make') and also disabling '@' operator so that the Makefile executes everything it's doing.
# Also modifies shell to use 'bash $2' to allow turning on debugging information for what the shell is doing.
define DEBUGMAKE
MAKEFLAGS+=--debug=$1
SHELL := bash $2
export EDEBUG := 1
endef

ifeq (${V},0)
.SILENT:
else ifeq (${V},1)
else ifeq (${V},2)
$(eval $(call DEBUGMAKE,b,-x))
else ifeq (${V},3)
$(eval $(call DEBUGMAKE,bv))
else ifeq (${V},4)
$(eval $(call DEBUGMAKE,bvi))
else ifeq (${V},5)
$(eval $(call DEBUGMAKE,bvij))
else ifeq (${V},6)
$(eval $(call DEBUGMAKE,bvijm))
else
$(error Unsupported Verbosity Level=${V})
endif

#----------------------------------------------------------------------------------------------------------------------
#
# TARGETS
#
#----------------------------------------------------------------------------------------------------------------------

.PHONY: ctags clean clobber

ctags: unittest/*.sh unittest/*.etest share/*.sh bin/*
	ctags -f .tags . $^

clean:
	git clean -fX
	bin/ebash rm -fr --one-file-system .forge/work

clobber: clean

lint:
	bin/bashlint

test:
	bin/etest --verbose=${V} --filter=${FILTER}

#----------------------------------------------------------------------------------------------------------------------
#
# Docker Tests
#
#----------------------------------------------------------------------------------------------------------------------

# Template for running tests inside a Linux distro container
DRUN = docker run --init --tty --interactive --privileged --mount type=bind,source=${PWD},target=/ebash --workdir /ebash --rm
define DOCKER_TEST_TEMPLATE

.PHONY: dselftest-$1
dselftest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && bin/selftest"

.PHONY: dtest-$1
dtest-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && bin/etest --break --verbose=${V} --filter=${FILTER}"

.PHONY: dshell-$1
dshell-$1:
	bin/ebanner "$2 Dependencies"
	${DRUN} $2 sh -c "bin/ebash-install-deps && /bin/bash"

endef

DISTROS =			\
	alpine:3.11		\
	alpine:3.12		\
	archlinux		\
	centos:8		\
	centos:7		\
	debian:10		\
	debian:9		\
	fedora:33		\
	fedora:32		\
	gentoo/stage3	\
	ubuntu:20.04	\
	ubuntu:18.04	\
	ubuntu:16.04	\

$(foreach t,${DISTROS},$(eval $(call DOCKER_TEST_TEMPLATE,$(subst :,-,$t),${t})))

PHONY: dtest
dtest:	    $(foreach d, $(subst :,-,${DISTROS}), dtest-${d})
dselftest:  $(foreach d, $(subst :,-,${DISTROS}), dselftest-${d})
