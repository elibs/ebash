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
CACHE    ?= $(or ${cache},1)
COLUMNS  ?= $(or ${columns},$(shell tput cols))
DELETE   ?= $(or ${delete},1)
EDEBUG   ?= $(or $(or ${edebug},${debug},))
EXCLUDE  ?= $(or ${exclude},)
FAILFAST ?= $(or ${failfast},0)
FAILURES ?= $(or ${failures},0)
FILTER   ?= $(or ${filter},)
JOBS     ?= $(or ${jobs},1)
PROGRESS ?= $(or ${progress},1)
PULL     ?= $(or ${pull},0)
PUSH     ?= $(or ${push},0)
REGISTRY ?= $(or ${registry},ghcr.io)
REPEAT   ?= $(or ${repeat},0)
V        ?= $(or $v,0)

# Variables that need to be exported to be seen by external processes we exec.
ENVLIST  ?= CACHE COLUMNS EDEBUG EXCLUDE FAILFAST FAILURES FILTER JOBS PRETEND PROGRESS PULL PUSH REGISTRY REPEAT V
export ${ENVLIST}

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
		--debug="${EDEBUG}"         \
		--delete=${DELETE}          \
		--exclude="${EXCLUDE}"      \
		--failfast=${FAILFAST}      \
		--filter="${FILTER}"        \
		--jobs=${JOBS}              \
		--jobs-progress=${PROGRESS} \
		--repeat=${REPEAT}          \
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
DRUN = bin/ebash docker_run                                 \
	--envlist "${ENVLIST}"                                  \
	--nested                                                \
	--copy-to-volume   "ebash:${PWD}:/ebash"                \
	--copy-from-volume "ebash:/ebash/.work:.work/docker/$1" \
	--copy-from-volume-delete ".work/docker/$1/docker"      \
	--                                                      \
	--init                                                  \
	--tty                                                   \
	--network host                                          \
	--privileged                                            \
	--rm                                                    \
	--workdir /ebash                                        \
	$$$$(cat .work/docker/ebash-build-$1/image)

#-----------------------------------------------------------------------------------------------------------------------
# Docker template
#-----------------------------------------------------------------------------------------------------------------------
define DOCKER_TEMPLATE

ifeq ($1,gentoo)
${1}_IMAGE_BASE = gentoo/stage3
else ifneq (,$(findstring rocky,$1))
${1}_IMAGE_BASE = rockylinux/$(subst rocky,rockylinux,$(subst -,:,$1))
else
${1}_IMAGE_BASE = $(subst -,:,$1)
endif

${1}_IMAGE = ghcr.io/elibs/ebash-build-$1
${1}_IMAGE_FULL = $(shell cat .work/docker/ebash-build-$1/image 2>/dev/null)

.PHONY: dlint-$1
dlint-$1: docker-$1
	rm -rf .work/docker/$1
	${DRUN} make lint

.PHONY: dselftest-$1
dselftest-$1: docker-$1
	rm -rf .work/docker/$1
	${DRUN} make selftest

.PHONY: dtest-$1
dtest-$1: docker-$1
	rm -rf .work/docker/$1
	${DRUN} make test

.PHONY: dshell-$1
dshell-$1: docker-$1
	rm -rf .work/docker/$1
	${DRUN} /bin/bash

.PHONY: docker-$1
docker-$1:
	bin/ebanner "Building Docker Image '$${$1_IMAGE}'" REGISTRY PULL PUSH
	bin/ebash docker_build                   \
		--file docker/Dockerfile.build       \
		--ibuild-arg IMAGE=$${$1_IMAGE_BASE} \
		--name $${$1_IMAGE}                  \
		--pull=${PULL}                       \
		--push=${PUSH}                       \
		--registry=${REGISTRY}               \
		--cache=${CACHE}                     \

.PHONY: docker-push-$1
docker-push-$1: docker-$1
	bin/einfo "Pushing $${$1_IMAGE_FULL})"
	docker push $${$1_IMAGE_FULL}

endef

$(foreach t, ${DISTROS},$(eval $(call DOCKER_TEMPLATE,${t})))

PHONY: dlint
dlint: $(foreach d, ${DISTROS}, dlint-${d})

PHONY: dtest
dtest: $(foreach d, ${DISTROS}, dtest-${d})

.PHONY: dselftest
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
