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

#-------------------------------------------------------------------------------
# create a pack containing the network namespace parameters
#
# Args: <pack name> <optional parameter pair list>
#
# ex: netns_init nsparams ns_name=mynamespace devname=mynamespace_eth0       \
#             peer_devname=eth0 connected_nic=eth0 bridge_cidr=<ipaddress>   \
#             nic_cidr=<ipaddress>
#
#  Where the options are:
#        ns_name        : The namespace name
#        devname        : veth pair's external dev name
#        peer_devname   : veth pair's internal dev name
#        connected_nic  : nic that can talk to the internet
#        bridge_cidr    : cidr for the bridge (ex: 1.2.3.4/24)
#        nic_cidr       : cidr for the internal nic (peer_devname)
#
netns_init()
{
    $(declare_args pack)

    pack_set ${pack}      \
        pack_name=${pack} \
        ns_name=          \
        devname=          \
        peer_devname=     \
        connected_nic=    \
        bridge_cidr=      \
        nic_cidr=         \
        "${@}"

    return 0
}

#-------------------------------------------------------------------------------
# Ensure that the minimum parameters to set up a namespace are present in the pack
#    and that the parameters meet some minimum criteria in form and/or length
#
# Args: <pack name>
#
netns_check_pack()
{
    $(declare_args pack)

    for key in ns_name devname peer_devname connected_nic bridge_cidr nic_cidr
    do
        if ! pack_contains ${pack} $key ; then
            pack_set $(pack_get $pack pack_name) API_Error_message="ERROR: pack key missing ($key)"
            return 1
        fi
    done

    $(pack_import $pack ns_name bridge_cidr nic_cidr)

    if [ ${#ns_name} -gt 12 ] ; then
        pack_set $(pack_get $pack pack_name) API_Error_message="ERROR: namespace name too long"
        return 1
    fi

    local REGEX="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}"

    if ! [[ $bridge_cidr =~ $REGEX ]] ; then
        pack_set $(pack_get $pack pack_name) API_Error_message="ERROR: bridge cidr is wrong"
        return 1
    fi

    if ! [[ $nic_cidr =~ $REGEX ]] ; then
        pack_set $(pack_get $pack pack_name) API_Error_message="ERROR: bridge cidr is wrong"
        return 1
    fi

}

#-------------------------------------------------------------------------------
# Run a command in a netns chroot that already exists
#
# Args: <pack name> <chroot root dir> <command with args>
#
netns_chroot_exec()
{
    $(declare_args pack chroot_root)

    netns_exec $(pack_get $pack ns_name) chroot "${chroot_root}" "$@"
}

#-------------------------------------------------------------------------------
# Set up the network inside a network namespace
#
# This will give you a network that can talk to the outside world from within
# the namespace
#
# Args: <pack name>
#
netns_setup_connected_network()
{
    $(declare_args pack)

    netns_check_pack $pack

    $(pack_import $pack)

    echo 1 > /proc/sys/net/ipv4/ip_forward

    netns_exists $ns_name
    if [ $? -eq 1 ] ; then
        #namespace doesn't exist
        return 1
    fi

    if [ -L /sys/class/net/$devname ] ; then
        #device is already there, abort
        return 0
    fi

    ip link add dev $devname type veth peer name ${devname}p
    ip link set dev $devname up
    ip tuntap add ${ns_name}_t mode tap
    ip link set dev ${ns_name}_t up
    ip link add ${ns_name}_br type bridge

    ip link set ${ns_name}_t master ${ns_name}_br
    ip link set $devname master ${ns_name}_br

    ip addr add $bridge_cidr dev ${ns_name}_br

    ip link set ${ns_name}_br up

    ip link set ${devname}p netns $ns_name
    ip netns exec $ns_name ip link set dev ${devname}p name $peer_devname

    netns_add_iptables_rules $ns_name ${ns_name}_br $connected_nic

    ip netns exec $ns_name ip addr add $nic_cidr dev ${peer_devname}
    ip netns exec $ns_name ip link set dev ${peer_devname} up
    ip netns exec $ns_name ip route add default via ${bridge_cidr//\/[0-9]*/}
}

#-------------------------------------------------------------------------------
# Remove the namespace network
#
# Args: <pack name>
#
netns_remove_network()
{
    $(declare_args pack)

    netns_check_pack $pack

    $(pack_import $pack ns_name connected_nic)

    local d

    for d in /sys/class/net/${ns_name}*
    do
      if [ -L $d ] ; then
          local bn=$(basename $d)
          ip link set $bn down
          ip link delete $bn
      fi
    done

    netns_remove_iptables_rules $ns_name ${ns_name}_br $connected_nic
}

#-------------------------------------------------------------------------------
# Add routing rules to the firewall to let traffic in/out of the namespace
#
# Args: <pack name> <additional targets to remove>
#
netns_add_iptables_rules()
{
    $(declare_args pack)

    netns_check_pack $pack

    $(pack_import $pack ns_name)

    local d

    for d in $@ ; do
        $(tryrc netns_iptables_rule_exists $ns_name $d)
        [[ $rc -eq 0 ]] && continue
        iptables -t nat -A POSTROUTING -o $d -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
# Remove routing rules added from above
#
# Args: <pack name> <device name>...
#
netns_remove_iptables_rules()
{
    $(declare_args pack)

    netns_check_pack $pack

    $(pack_import $pack ns_name)

    for d in $@ ; do
        $(tryrc netns_iptables_rule_exists $ns_name $d)
        [[ $rc -ne 0 ]] && continue
        iptables -t nat -D POSTROUTING -o $d -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
# Check if a rule exists for a given nic in the namespace
#
# Args: <pack name> <device name>
#
netns_iptables_rule_exists()
{
    $(declare_args pack devname)

    netns_check_pack $pack

    $(pack_import $pack ns_name)

    iptables -t nat -nvL|sed -n '/POSTROUTING/,/^$/p'|grep -v "^$"|tail -n -2|grep -q $devname
    return $?
}

