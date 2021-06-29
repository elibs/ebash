#!/bin/bash
#
# Copyright 2015-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2015-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

[[ ${__EBASH_OS} != Linux ]] && return 0

EBASH_NETNS_DIR="/run/netns"

opt_usage netns_supported <<'END'
Check which network namespace features are supported.
END
netns_supported()
{
    $(opt_parse "?area=all")

    local valid_areas=( "all" "user" "iptables" )

    array_contains valid_areas "${area}" || die "netns_supported: Invalid area [${area}]"

    if [[ ${area} =~ all|user ]] ; then
       if [[ $(id -u) -ne 0 ]] ; then
          edebug "netns_supported: Invalid User"
          return 1
       fi
    fi

    if [[ ${area} =~ all|iptables ]] ; then
       if ! grep -q nat /proc/net/ip_tables_names ; then
          edebug "netns_supported: no iptables nat support"
          return 1
       fi
    fi

    return 0
}

opt_usage netns_create <<'END'
Idempotent create a network namespace.
END
netns_create()
{
    $(opt_parse ns_name)

    # Do not create if it already exists
    [[ -e "${EBASH_NETNS_DIR}/${ns_name}" ]] && return 0

    ip netns add "${ns_name}"
    netns_exec "${ns_name}" ip link set dev lo up
}

opt_usage netns_delete <<'END'
Idempotent delete a network namespace.
END
netns_delete()
{
    $(opt_parse ns_name)

    # Do not delete if it does not exist
    [[ ! -e "${EBASH_NETNS_DIR}/${ns_name}" ]] && return 0

    netns_exec "${ns_name}" ip link set dev lo down
    ip netns delete "${ns_name}"
}

opt_usage netns_exec <<'END'
Execute a command in the given network namespace.
END
netns_exec()
{
    $(opt_parse ns_name)
    ip netns exec "${ns_name}" "$@"
}

opt_usage netns_list <<'END'
Get a list of network namespaces.
END
netns_list()
{
    ip netns list | sort
}

opt_usage netns_exists <<'END'
Check if a network namespace exists.
END
netns_exists()
{
    $(opt_parse ns_name)
    [[ -e "${EBASH_NETNS_DIR}/${ns_name}" ]] && return 0 || return 1
}

opt_usage netns_init <<'END'
create a pack containing the network namespace parameters

example:
```shell
netns_init nsparams ns_name=mynamespace devname=mynamespace_eth0       \
        peer_devname=eth0 connected_nic=eth0 bridge_cidr=<ipaddress>   \
        nic_cidr=<ipaddress>
```

Where the options are:
- **ns_name**        : The namespace name
- **devname**        : veth pair's external dev name
- **peer_devname**   : veth pair's internal dev name
- **connected_nic**  : nic that can talk to the internet
- **bridge_cidr**    : cidr for the bridge (ex: `1.2.3.4/24`)
- **nic_cidr**       : cidr for the internal nic (peer_devname)
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

    array_empty netns_options || pack_set ${netns_args_packname} "${netns_options[@]}"

    return 0
}

opt_usage netns_check_pack <<'END'
Ensure that the minimum parameters to set up a namespace are present in the pack and that the
parameters meet some minimum criteria in form and/or length
END
netns_check_pack()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information. (Was created by netns
                               init with a name you chose)")

    local key
    for key in ns_name devname peer_devname connected_nic bridge_cidr nic_cidr ; do
        if ! pack_contains ${netns_args_packname} ${key} ; then
            die "ERROR: netns_args key missing (${key})"
        fi
    done

    $(pack_import ${netns_args_packname})

    [[ ${#ns_name} -le 12 ]] || die "ERROR: namespace name too long (Max: 12 chars)"
    [[ ${#devname} -le 16 ]] || die "ERROR: devname too long (Max: 16 chars)"
    [[ ${#peer_devname} -le 16 ]] || die "ERROR: peer_devname too long (Max: 16 chars)"
    [[ ${#connected_nic} -le 16 ]] || die "ERROR: connected_nic too long (Max: 16 chars)"

    # a cidr is an ip address with the number of static (or network) bits added to the end. It is typically of the form
    # "A.B.C.D/##". the "ip" utility uses cidr addresses rather than netmasks, as they serve the same purpose. This
    # regex ensures that the address is a cidr address.
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

opt_usage netns_chroot_exec <<'END'
Run a command in a netns chroot that already exists.
END
netns_chroot_exec()
{
    $(opt_parse \
        "netns_args_packname | Name of variable containing netns information. (Was created by netns
                               init with a name you chose)" \
        "chroot_root         | Existing chroot to run within." \
        "@command            | Command and arguments.")

    $(pack_import ${netns_args_packname} ns_name)

    edebug "Executing command in namespace [${ns_name}] and chroot [${chroot_root}]: ${cmd[*]}"
    netns_exec ${ns_name} chroot "${chroot_root}" "${cmd[@]}"
}
