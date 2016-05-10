#!/bin/bash
#
# Copyright 2015, SolidFire, Inc. All rights reserved.

[[ ${__BU_OS} != Linux ]] && return 0

NETNS_DIR="/run/netns"

#-------------------------------------------------------------------------------
opt_usage netns_create "Idempotent create a network namespace"
netns_create()
{
    $(opt_parse ns_name)

    # Do not create if it already exists
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    ip netns add "${ns_name}"
    netns_exec "${ns_name}" ip link set dev lo up
}

#-------------------------------------------------------------------------------
opt_usage netns_delete "Idempotent delete a network namespace"
netns_delete()
{
    $(opt_parse ns_name)

    # Do not delete if it does not exist
    [[ ! -e "${NETNS_DIR}/${ns_name}" ]] && return 0

    netns_exec "${ns_name}" ip link set dev lo down
    ip netns delete "${ns_name}"
}

#-------------------------------------------------------------------------------
opt_usage netns_exec "Execute a command in the given network namespace"
netns_exec()
{
    $(opt_parse ns_name)
    ip netns exec "${ns_name}" "$@"
}

#-------------------------------------------------------------------------------
opt_usage netns_list "Get a list of network namespaces"
netns_list()
{
    ip netns list | sort
}

#-------------------------------------------------------------------------------
opt_usage netns_exists "Check if a network namespace exists"
netns_exists()
{
    $(opt_parse ns_name)
    [[ -e "${NETNS_DIR}/${ns_name}" ]] && return 0 || return 1
}

#-------------------------------------------------------------------------------
opt_usage netns_init <<'END'
create a pack containing the network namespace parameters

example: netns_init nsparams ns_name=mynamespace devname=mynamespace_eth0       \
            peer_devname=eth0 connected_nic=eth0 bridge_cidr=<ipaddress>   \
            nic_cidr=<ipaddress>

 Where the options are:
       ns_name        : The namespace name
       devname        : veth pair's external dev name
       peer_devname   : veth pair's internal dev name
       connected_nic  : nic that can talk to the internet
       bridge_cidr    : cidr for the bridge (ex: 1.2.3.4/24)
       nic_cidr       : cidr for the internal nic (peer_devname)

END
netns_init()
{
    $(opt_parse \
        "netns_args_packname | Name of variable that will be used to hold this netns's information." \
        "@netns_options      | Network namespace options to use in form option=value")

    pack_set ${netns_args_packname}             \
        netns_args_name=${netns_args_packname}  \
        ns_name=                                \
        devname=                                \
        peer_devname=                           \
        connected_nic=                          \
        bridge_cidr=                            \
        nic_cidr=

    array_empty netns_options || pack_set "${netns_options[@]}"

    return 0
}

#-------------------------------------------------------------------------------
opt_usage netns_check_pack <<'END'
Ensure that the minimum parameters to set up a namespace are present in the pack and that the
parameters meet some minimum criteria in form and/or length
END
netns_check_pack()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)")

    local key
    for key in ns_name devname peer_devname connected_nic bridge_cidr nic_cidr ; do
        if ! pack_contains ${netns_args_packname} ${key} ; then
            die "ERROR: netns_args key missing (${key})"
        fi
    done

    $(pack_import ${netns_args_packname} ns_name bridge_cidr nic_cidr)

    if [[ ${#ns_name} -gt 12 ]] ; then
        die "ERROR: namespace name too long (Max: 12 chars)"
    fi

    # a cidr is an ip address with the number of static (or network) bits 
    # added to the end.  It is typically of the form "A.B.C.D/##".  the "ip"
    # utility uses cidr addresses rather than netmasks, as they serve the same
    # purpose.  This regex ensures that the address is a cidr address.
    local cidr_regex="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}"

    if ! [[ ${bridge_cidr} =~ ${cidr_regex} ]] ; then
        edebug "ERROR: bridge_cidr is wrong [${bridge_cidr}]"
        pack_set $(pack_get ${netns_args_packname} netns_args_name) API_Error_message="ERROR: bridge_cidr is wrong [${bridge_cidr}]"
        return 1
    fi

    if ! [[ ${nic_cidr} =~ ${cidr_regex} ]] ; then
        edebug "ERROR: nic_cidr is wrong [${nic_cidr}]"
        pack_set $(pack_get ${netns_args_packname} netns_args_name) API_Error_message="ERROR: nic_cidr is wrong [${nic_cidr}]"
        return 1
    fi
}

#-------------------------------------------------------------------------------
opt_usage netns_chroot_exec "Run a command in a netns chroot that already exists"
netns_chroot_exec()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)" \
        "chroot_root         | Existing chroot to run within." \
        "@command            | Command and arguments.")

    $(pack_import ${netns_args_packname} ns_name)

    edebug "Executing command in namespace [${ns_name}] and chroot [${chroot_root}]: ${cmd[@]}"
    netns_exec ${ns_name} chroot "${chroot_root}" "${cmd[@]}"
}

#-------------------------------------------------------------------------------
opt_usage netns_setup_connected_network <<'END'
Set up the network inside a network namespace This will give you a network that can talk to the
outside world from within the namespace

Note: https://superuser.com/questions/764986/howto-setup-a-veth-virtual-network

END
netns_setup_connected_network()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)")

    netns_check_pack ${netns_args_packname}

    $(pack_import ${netns_args_packname})

    # this allows packets to come in on the real nic and be forwarded to the
    # virtual nic.  It turns on routing in the kernel.
    echo 1 > /proc/sys/net/ipv4/ip_forward

    $(tryrc netns_exists ${ns_name})
    if [[ ${rc} -eq 1 ]] ; then
        edebug "ERROR: namespace [${ns_name}] does not exist"
        return 1
    fi

    if [[ -L /sys/class/net/${devname} ]] ; then
        edebug "WARN: device (${devname}) already exists, returning"
        return 0
    fi

    # We create all the virtual things we need.  A veth pair, a tap adapter
    # and a virtual bridge
    ip link add dev ${devname} type veth peer name ${devname}p
    ip link set dev ${devname} up
    ip tuntap add ${ns_name}_t mode tap
    ip link set dev ${ns_name}_t up
    ip link add ${ns_name}_br type bridge

    # put the tap adapter in the bridge
    ip link set ${ns_name}_t master ${ns_name}_br

    # put one end of the veth pair in the bridge
    ip link set ${devname} master ${ns_name}_br

    # give the bridge a cidr address (a.b.c.d/##)
    ip addr add ${bridge_cidr} dev ${ns_name}_br

    # bring up the bridge
    ip link set ${ns_name}_br up

    # put the other end of the veth pair in the namespace
    ip link set ${devname}p netns ${ns_name}

    # and rename the nic in the namespace to what was specified in the args
    ip netns exec ${ns_name} ip link set dev ${devname}p name ${peer_devname}

    # Add iptables rules to allow the bridge and the connected nic to MASQARADE
    netns_add_iptables_rules ${netns_args_packname}

    #add the cidr address to the nic in the namespace
    ip netns exec ${ns_name} ip addr add ${nic_cidr} dev ${peer_devname}
    ip netns exec ${ns_name} ip link set dev ${peer_devname} up

    # Add a route so that the namespace can communicate out
    ip netns exec ${ns_name} ip route add default via ${bridge_cidr//\/[0-9]*/}

    #DNS is taken care of by the filesystem (either in a chroot or outside)
}

#-------------------------------------------------------------------------------
opt_usage netns_remove_network "Remove the namespace network"
netns_remove_network()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)")

    netns_check_pack ${netns_args_packname}

    $(pack_import ${netns_args_packname} ns_name connected_nic)

    local device
    for device in /sys/class/net/${ns_name}* ; do
      if [[ -L ${device} ]] ; then
          local basename_device=$(basename ${device})
          ip link set ${basename_device} down
          ip link delete ${basename_device}
      fi
    done

    netns_remove_iptables_rules ${netns_args_packname}
}

#-------------------------------------------------------------------------------
opt_usage netns_add_iptables_rules <<'END'
Add routing rules to the firewall to let traffic in/out of the namespace
END
netns_add_iptables_rules()
{
    $(opt_parse
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)")

    netns_check_pack ${netns_args_packname}

    $(pack_import ${netns_args_packname} ns_name connected_nic)

    local device
    for device in ${ns_name}_br ${connected_nic} ${@} ; do
        $(tryrc netns_iptables_rule_exists ${netns_args_packname} ${device})
        [[ ${rc} -eq 0 ]] && continue
        iptables -t nat -A POSTROUTING -o ${device} -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
opt_usage netns_remove_iptables_rules <<'END'
Remove routing rules added from above
END
netns_remove_iptables_rules()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)")

    netns_check_pack ${netns_args_packname}

    $(pack_import ${netns_args_packname} ns_name connected_nic)

    local device
    for device in ${ns_name}_br ${connected_nic} ${@} ; do
        $(tryrc netns_iptables_rule_exists ${netns_args_packname} ${device})
        [[ ${rc} -ne 0 ]] && continue
        iptables -t nat -D POSTROUTING -o ${device} -j MASQUERADE
    done
}

#-------------------------------------------------------------------------------
opt_usage netns_iptables_rule_exists <<'END'
# Check if a rule exists for a given nic in the namespace
END
netns_iptables_rule_exists()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information.  (Was created by netns
                               init with a name you chose)" \
        "devname             | Network device to operate on.")

    netns_check_pack ${netns_args_packname}

    $(pack_import ${netns_args_packname} ns_name)

    iptables -t nat -nvL           | \
      sed -n '/POSTROUTING/,/^$/p' | \
      grep -v "^$"                 | \
      tail -n -2                   | \
      grep -q ${devname}
}

return 0
