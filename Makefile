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
EDEBUG   ?= $(or $(or ${edebug},${debug},))
EXCLUDE  ?= $(or ${exclude},)
FAILFAST ?= $(or ${failfast},0)
FILTER   ?= $(or ${filter},)
REPEAT   ?= $(or ${repeat},0)
V        ?= $(or $v,0)

.SILENT:

#----------------------------------------------------------------------------------------------------------------------
#
# Targets
#
#----------------------------------------------------------------------------------------------------------------------

.PHONY: ctags
ctags: tests/*.sh tests/*.etest share/*.sh bin/*
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

.PHONY: lint bashlint
lint bashlint:
	bin/bashlint --failfast=${FAILFAST} --internal --severity=error --filter=${FILTER} --exclude=${EXCLUDE}

.PHONY: selftest
selftest:
	bin/selftest

.PHONY: test
test:
	bin/etest \
		--debug="${EDEBUG}"     \
		--exclude="${EXCLUDE}"  \
		--failfast=${FAILFAST}  \
		--filter="${FILTER}"    \
		--repeat=${REPEAT}      \
		--verbose=${V}

.PHONY: doc
doc:
	bin/edoc

#----------------------------------------------------------------------------------------------------------------------
#
# Docker
#
#----------------------------------------------------------------------------------------------------------------------

DISTROS =           \
	alpine-3.15     \
	alpine-3.14     \
	archlinux       \
	centos-8        \
	centos-7        \
	debian-11       \
	debian-10       \
	fedora-35       \
	fedora-33       \
	gentoo          \
	rocky-8         \
	ubuntu-20.04    \
	ubuntu-18.04    \

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

define DOCKER_TEMPLATE

ifeq ($1,gentoo)
${1}_IMAGE_BASE = gentoo/stage3
else ifneq (,$(findstring rocky,$1))
${1}_IMAGE_BASE = rockylinux/$(subst rocky,rockylinux,$(subst -,:,$1))
else
${1}_IMAGE_BASE = $(subst -,:,$1)
endif

${1}_IMAGE = ghcr.io/elibs/ebash-build-$1

.PHONY: dselftest-$1
dselftest-$1: docker-$1
	${DRUN} $${$1_IMAGE} bin/selftest

.PHONY: dtest-$1
dtest-$1: docker-$1
	${DRUN} $${$1_IMAGE} bin/etest \
		--break                      \
		--debug="${EDEBUG}"          \
		--exclude="${EXCLUDE}"       \
		--filter="${FILTER}"         \
		--log-dir=.work              \
		--repeat=${REPEAT}           \
		--verbose=${V}               \
		--work-dir=.work/output

.PHONY: dshell-$1
dshell-$1: docker-$1
	${DRUN} $${$1_IMAGE} /bin/bash

.PHONY: docker-$1
docker-$1:
	bin/ebash docker_build                   \
		--name $${$1_IMAGE}                  \
		--tag $${$1_IMAGE}:latest            \
		--ibuild-arg IMAGE=$${$1_IMAGE_BASE} \
		--file docker/Dockerfile.build       \
		--registry ghcr.io                   \
		--pull                               \

#docker build -t $${$1_IMAGE} --build-arg IMAGE=$${$1_IMAGE_BASE} -f docker/Dockerfile.build .

.PHONY: docker-push-$1
docker-push-$1:
	bin/ebanner "Publishing $2 Docker Image"
	docker push $${$1_IMAGE}

endef

$(foreach t, ${DISTROS},$(eval $(call DOCKER_TEMPLATE,${t})))

PHONY: dtest
dtest:	    $(foreach d, ${DISTROS}, dtest-${d})
dselftest:  $(foreach d, ${DISTROS}, dselftest-${d})

.PHONY: docker
docker: $(foreach d, ${DISTROS}, docker-${d})

.PHONY: docker-push
docker-push: $(foreach d, ${DISTROS}, docker-push-${d})

#-----------------------------------------------------------------------------------------------------------------------
#
# INTROSPECTION
#
#-----------------------------------------------------------------------------------------------------------------------

# List targets the Makefile knows about
.PHONY: help targets usage
HELP_EXCLUDE_RE = Makefile|help|print-%|targets|usage
help targets usage:
	echo "Targets"
	echo "======="
	{ MAKEFLAGS= ${MAKE} -qp \
		| awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /); for(i in A) print A[i]}' \
		| grep -Pv "${HELP_EXCLUDE_RE}" ; } \
		| sort --unique

# Make print-VARNAME for any variable will print its value
print-% :
	echo $($*)

# Print all Make variables
.PHONY: printvars
PRINTVARS_EXCLUDES=%_TEMPLATE DEBUGMAKE LAZY_INIT
printvars:
	echo -n $(foreach v,$(sort $(filter-out ${PRINTVARS_EXCLUDES},${.VARIABLES})),\
		$(if $(filter-out environment% default automatic,\
			$(origin $v)),$(info $(v)=$($(v)))))

.PHONY: printenv
printenv:
	{ go env ; printenv ; } | sort | grep -Pv '(LS_COLORS|LESS_TERMCAP)'
