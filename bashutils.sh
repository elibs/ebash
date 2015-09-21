#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

source ${BASHUTILS}/efuncs.sh
$(esource                       \
    ${BASHUTILS}/cgroup.sh      \
    ${BASHUTILS}/chroot.sh      \
    ${BASHUTILS}/daemon.sh      \
    ${BASHUTILS}/dpkg.sh        \
    ${BASHUTILS}/jenkins.sh     \
    ${BASHUTILS}/omconfig.sh    \
    ${BASHUTILS}/plymouth.sh    \
    )
