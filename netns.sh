#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.


NETNS_DIR="/run/netns"

#-------------------------------------------------------------------------------
# Idempotent create a network namespace
#
netns_create()
{
    $(declare_args ns_name)

    # Do not create if it already exists
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    ip netns add "${ns_name}"
    netns_exec "${ns_name}" ip link set dev lo up
}

#-------------------------------------------------------------------------------
# Idempotent delete a network namespace
#
netns_delete()
{
    $(declare_args ns_name)

    # Do not delete if it does not exist
    [[ ! -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    netns_exec "${ns_name}" ip link set dev lo down
    ip netns delete "${ns_name}"
}

#-------------------------------------------------------------------------------
# Execute a command in the given network namespace
#
netns_exec()
{
    $(declare_args ns_name)
    ip netns exec "${ns_name}" "$@"
}

#-------------------------------------------------------------------------------
# Get a list of network namespaces
#
netns_list()
{
    ip netns list | sort
}

#-------------------------------------------------------------------------------
# Check if a network namespace exists
#
netns_exists()
{
    $(declare_args ns_name)
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0 || return 1
}
