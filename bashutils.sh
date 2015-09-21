#!/usr/bin/env bash
#
# Copyright 2011-2015, SolidFire, Inc. All rights reserved.
#

source ${BASHUTILS}/efuncs.sh
$(esource       \
    cgroup.sh   \
    chroot.sh   \
    daemon.sh   \
    dpkg.sh     \
    jenkins.sh  \
    omconfig.sh \
    plymouth.sh \
    )
