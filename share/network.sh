#!/usr/bin/env bash
#
# Copyright 2011-2018, Marshall McMullen <marshall.mcmullen@gmail.com>
# Copyright 2011-2018, SolidFire, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify it under the terms of the Apache License
# as published by the Apache Software Foundation, either version 2 of the License, or (at your option) any later
# version.

# Set root of sysfs tree for easier mockability in unit tests
SYSFS="/sys"

opt_usage valid_ip <<'END'
Check if a given input is a syntactically valid IP Address.
END
valid_ip()
{
    $(opt_parse ip)
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        array_init ip "${ip}" "."
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

opt_usage hostname_to_ip <<'END'
Convert a given hostname to its corresponding IP Address.
END
hostname_to_ip()
{
    $(opt_parse hostname)

    local output=""
    output="$(host ${hostname} | grep ' has address ' || true)"

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    ip=$(echo ${output} | awk '{print $4}')

    valid_ip ${ip}
    echo ${ip}
    return 0
}

opt_usage fully_qualify_hostname <<'END'
Convert the provided hostname into a fully qualified hostname.
END
fully_qualify_hostname()
{
    local hostname=${1,,}
    argcheck hostname

    try
    {
        local output
        output=$(host ${hostname})

        [[ ${output} =~ " has address " ]]
        local fqhostname
        fqhostname=$(echo ${output} | awk '{print $1}')
        echo "${fqhostname,,}"
    }
    catch
    {
        ewarn "Unable to resolve ${hostname}"
        return 1
    }

    return 0
}

opt_usage getipaddress <<'END'
Get the IPAddress currently bound to the requested interface (if any). It is not an error for an interface to be unbound
so this function will not fail if no IPAddress is set on the interface. Instead it will simply return an empty string.
END
getipaddress()
{
    $(opt_parse iface)
    ip addr show "${iface}" 2>/dev/null \
        | awk '/inet [0-9.\/]+.* scope global.* '${iface}'$/ { split($2, arr, "/"); print arr[1] }' 2>/dev/null || true
}

opt_usage getnetmask <<'END'
Get the netmask (IPv4 dotted notation) currently set on the requested interface (if any). It is not an error for an
interface to be unbound so this method will not fail if no Netmask has been set on an interface. Instead it will simply
return an empty string.
END
getnetmask()
{
    $(opt_parse iface)
    local cidr
    cidr=$(ip addr show "${iface}" 2>/dev/null | awk '/inet [0-9.\/]+ .* scope global.* '${iface}'$/ { split($2, arr, "/"); print arr[2] }' || true)
    [[ -z "${cidr}" ]] && return 0

    cidr2netmask "${cidr}"
}

opt_usage netmask2cidr <<'END'
Convert a netmask in IPv4 dotted notation into CIDR notation (e.g `255.255.255.0` => `24`). Below is the official chart
of all possible valid Netmasks in quad-dotted decimal notation with the associated CIDR value:

```shell
{ "255.255.255.255", 32 }, { "255.255.255.254", 31 }, { "255.255.255.252", 30 }, { "255.255.255.248", 29 },
{ "255.255.255.240", 28 }, { "255.255.255.224", 27 }, { "255.255.255.192", 26 }, { "255.255.255.128", 25 },
{ "255.255.255.0",   24 }, { "255.255.254.0",   23 }, { "255.255.252.0",   22 }, { "255.255.248.0",   21 },
{ "255.255.240.0",   20 }, { "255.255.224.0",   19 }, { "255.255.192.0",   18 }, { "255.255.128.0",   17 },
{ "255.255.0.0",     16 }, { "255.254.0.0",     15 }, { "255.252.0.0",     14 }, { "255.248.0.0",     13 },
{ "255.240.0.0",     12 }, { "255.224.0.0",     11 }, { "255.192.0.0",     10 }, { "255.128.0.0",      9 },
{ "255.0.0.0",        8 }, { "254.0.0.0",        7 }, { "252.0.0.0",        6 }, { "248.0.0.0",        5 },
{ "240.0.0.0",        4 }, { "224.0.0.0",        3 }, { "192.0.0.0",        2 }, { "128.0.0.0",        1 },
```

From: https://forums.gentoo.org/viewtopic-t-888736-start-0.html
END
netmask2cidr ()
{
    # Assumes there's no "255." after a non-255 byte in the mask
    set -- 0^^^128^192^224^240^248^252^254^ ${#1} ${1##*255.}
    set -- $(( ($2 - ${#3})*2 )) ${1%%${3%%.*}*}
    local rem="${2:-}"
    echo $(( $1 + (${#rem}/4) ))
}

opt_usage cidr2netmask <<'END'
Convert a netmask in CIDR notation to an IPv4 dotted notation (e.g. `24` => `255.255.255.0`). This function takes input in
the form of just a singular number (e.g. `24`) and will echo to standard output the associated IPv4 dotted notation form
of that netmask (e.g. `255.255.255.0`).

See comments in netmask2cidr for a table of all possible netmask/cidr mappings.

From: https://forums.gentoo.org/viewtopic-t-888736-start-0.html
END
cidr2netmask()
{
    # Number of args to shift, 255..255, first non-255 byte, zeroes
    set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
    [[ $1 -gt 1 ]] && shift $1 || shift
    echo ${1-0}.${2-0}.${3-0}.${4-0}
}

opt_usage getbroadcast <<'END'
Get the broadcast address for the requested interface, if any. It is not an error for a network interface not to have a
broadcast address associated with it (e.g. loopback interfaces). If no broadcast address is set this will just echo an
empty string.
END
getbroadcast()
{
    $(opt_parse iface)
    ip addr show "${iface}" 2>/dev/null \
        | awk '/inet [0-9.\/]+ brd .* scope global (dynamic )*'${iface}'$/ { print $4 }' || true
}

opt_usage getgateway <<'END'
Gets the default gateway that is currently in use, if any. It is not an error for there to be no gateway set. In that
case this will simply echo an empty string.
END
getgateway()
{
    $(opt_parse iface)
    route -n | awk '/UG[ \t].*'${iface}'$/ { print $2 }' | sort --unique || true
}

opt_usage getsubnet <<'END'
Compute the subnet given the current IPAddress (ip) and Netmask (nm). If either the provided IPAddress or Netmask is
empty then we cannot compute the subnet. As it's not an error to have no IPAddress or Netmask assigned to an unbound
interface, getsubnet will not fail in this case. The output will be an empty string and it will return 0.
END
getsubnet()
{
    $(opt_parse "?ip" "?nm")
    [[ -z "${ip}" || -z "${nm}" ]] && return 0

    IFS=. read -r i1 i2 i3 i4 <<< "${ip}"
    IFS=. read -r m1 m2 m3 m4 <<< "${nm}"

    printf "%d.%d.%d.%d" "$((i1 & m1))" "$(($i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

opt_usage getmtu <<'END'
Get the MTU that is currently set on a given interface.
END
getmtu()
{
    $(opt_parse iface)
    ip addr show "${iface}" 2>/dev/null | grep -Po 'mtu \K[\d.]+' || true
}

opt_usage getvlans <<'END'
Get the vlans on a given interface.
END
getvlans()
{
    $(opt_parse iface)

    ip link show type vlan 2>/dev/null | grep "[0-9]\+: ${iface}\." | cut -d: -f2 | cut -d. -f2 | cut -d@ -f1 || true
}

opt_usage get_network_interfaces <<'END'
Get list of network interfaces
END
get_network_interfaces()
{
    # On OSX just delegate this work to networksetup as the mac ports installed ip command doesn't support
    # "ip link show type" command.
    if os darwin; then
        networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2}'
    fi

    for iface in $(ls -1 ${SYSFS}/class/net); do
        # Skip virtual devices, we only want physical
        [[ ! -e ${SYSFS}/class/net/${iface}/device ]] && continue
        echo "${iface}"
    done | tr '\n' ' ' || true
}

opt_usage get_network_interfaces_with_port <<'END'
Get list network interfaces with specified "Supported Ports" query.
END
get_network_interfaces_with_port()
{
    local query ifname port
    local results=()

    for ifname in $(get_network_interfaces); do
        port=$(ethtool ${ifname} | grep "Supported ports:" || true)
        for query in $@; do
            if [[ ${port} =~ "${query}" ]]; then
                results+=( "${ifname}" )
                break
            fi
        done
    done

    echo -n "${results[@]:-}"
}

opt_usage get_network_interfaces_1g <<'END'
Get list of 1G network interfaces.
END
get_network_interfaces_1g()
{
    get_network_interfaces_with_port "TP"
}

opt_usage get_network_interfaces_10g <<'END'
Get list of 10G network interfaces.
END
get_network_interfaces_10g()
{
    get_network_interfaces_with_port "FIBRE" "Backplane"
}

opt_usage get_permanent_mac_address <<'END'
Get the permanent MAC address for given ifname.

> **_NOTE:_** `ethtool -P` is not reliable on all cards since the firmware has to support it properly. So on Linux we
instead look in SYSFS since this is far more reliable as we're talking direct to the kernel. But on OSX we instead just
use ethtool.
END
get_permanent_mac_address()
{
    $(opt_parse ifname)

    if os Linux; then
        if [[ -e ${SYSFS}/class/net/${ifname}/master ]]; then
            sed -n "/Slave Interface: ${ifname}/,/^$/p" /proc/net/bonding/$(basename $(readlink -f ${SYSFS}/class/net/${ifname}/master)) \
                | grep "Permanent HW addr" \
                | sed -e "s/Permanent HW addr: //"
        else
            cat ${SYSFS}/class/net/${ifname}/address
        fi
    elif command_exists ethtool; then
        ethtool -P "${ifname}" | sed -e 's|Permanent address: ||'
    else
        die "Unable to determine permanent MAC Address for $(lval ifname)"
    fi
}

opt_usage get_network_pci_device <<'END'
Get the PCI device location for a given ifname

> **_NOTE:_** This is only useful for physical devices, such as eth0, eth1, etc.
END
get_network_pci_device()
{
    $(opt_parse ifname)

    if ! os Linux; then
        die "Unable to determine PCI Device for $(lval ifname) on non-Linux"
    fi

    # Try with ethtool first (works on physical platforms and VMware, KVM, VirtualBox)
    local pci_addr
    pci_addr=$(ethtool -i ${ifname} | grep -Po "bus-info: \K.*" || true)

    # If that did not give a result (HyperV), fall back to looking at the device path in sysfs
    if [[ -z ${pci_addr} ]]; then
        pci_addr=$(cd ${SYSFS}/class/net/${ifname}/device; basename $(pwd -P))
    fi

    echo ${pci_addr}
}

opt_usage export_network_interface_names <<'END'
Export ethernet device names in the form ETH_1G_0=eth0, etc.
END
export_network_interface_names()
{
    local idx=0
    local ifname

    for ifname in $(get_network_interfaces_10g); do
        eval "ETH_10G_${idx}=${ifname}"
        (( idx+=1 ))
    done

    idx=0
    for ifname in $(get_network_interfaces_1g); do
        eval "ETH_1G_${idx}=${ifname}"
        (( idx+=1 ))
    done
}

opt_usage get_network_ports <<'END'
Get a list of the active network ports on this machine. The result is returned as an array of packs
stored in the variable passed to the function.

For example:

```shell
$ declare -A ports
$ get_listening_ports ports
$ einfo $(lval %ports[5])
>> ports[5]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="0.0.0.0" [local_port]="22" [remote_addr]="0.0.0.0" [remote_port]="0" [state]="LISTEN" [pid]="9278" [prog]="sshd" )
$ einfo $(lval %ports[42])
ports[42]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="172.17.5.208" [local_port]="48899" [remote_addr]="173.194.115.70" [remote_port]="443" [state]="ESTABLISHED" [pid]="28073" [prog]="chrome" )
```
END
get_network_ports()
{
    $(opt_parse \
        "+listening l | Only include listening ports" \
        "__ports_list")

    local idx=0
    local first=1
    while read line; do

        # Expected netstat format:
        #  Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
        #  tcp        0      0 10.30.65.166:4013       0.0.0.0:*               LISTEN      42004/sfapp
        #  tcp        0      0 10.30.65.166:4014       0.0.0.0:*               LISTEN      42002/sfapp
        #  tcp        0      0 10.30.65.166:8080       0.0.0.0:*               LISTEN      42013/sfapp
        #  tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      19221/sshd
        #  tcp        0      0 0.0.0.0:442             0.0.0.0:*               LISTEN      13159/sfconfig
        #  tcp        0      0 172.30.65.166:2222      192.168.138.137:35198   ESTABLISHED 6112/sshd: root@not
        # ...
        #  udp        0      0 0.0.0.0:123             0.0.0.0:*                           45883/ntpd
        #  udp        0      0 0.0.0.0:161             0.0.0.0:*                           39714/snmpd
        #  udp        0      0 0.0.0.0:514             0.0.0.0:*                           39746/rsyslogd
        #
        # If netstat cannot determine the program that is listening on that port (not enough permissions) it will substitute a "-":
        #  tcp        0      0 0.0.0.0:902             0.0.0.0:*               LISTEN      -
        #  udp        0      0 0.0.0.0:43481           0.0.0.0:*                           -
        #

        # Compare first line to make sure fields are what we expect
        if [[ ${first} -eq 1 ]]; then
            local expected_fields="Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program name"
            assert_eq "${expected_fields}" "${line}"
            first=0
            continue
        fi

        # Convert the line into an array for easy access to the fields
        # Replace * with 0 so that we don't get a glob pattern and end up with an array full of filenames from the local directory
        local fields
        array_init fields "$(echo ${line} | tr '*' '0')" " :/"

        # Skip this line if this is not TCP or UDP
        [[ ${fields[0]} =~ (tcp|udp) ]] || continue

        # Skip this line if the -l flag was passed in and this is not a listening port
        [[ ${listening} -eq 1 && ${fields[0]} == "tcp" && ! ${fields[7]} =~ "LISTEN" ]] && continue

        # If there is a - in the line, then netstat could not determine the program listening on this port.
        # Remove the - and add empty strings for the last two fields (PID and program name)
        if [[ ${line} =~ "-" ]]; then
            array_remove fields "-"
            fields+=("")
            fields+=("")
        fi

        # If this is a UDP port, insert an empty string into the "state" field
        if [[ ${fields[0]} == "udp" ]]; then
            fields[9]=${fields[8]}
            fields[8]=${fields[7]}
            fields[7]=""
        fi

        pack_set ${__ports_list}[${idx}] \
            proto=${fields[0]} \
            recvq=${fields[1]} \
            sendq=${fields[2]} \
            local_addr=${fields[3]} \
            local_port=${fields[4]} \
            remote_addr=${fields[5]} \
            remote_port=${fields[6]} \
            state=${fields[7]} \
            pid=${fields[8]} \
            prog=${fields[9]}

        (( idx += 1 ))

    done <<< "$(netstat --all --program --numeric --protocol=inet 2>/dev/null | sed '1d' | tr -s ' ')"
}

opt_usage netselect <<'END'
Netselect chooses the host that responds most quickly and reliably among a list of specified IP
addresses or hostnames. It does this by pinging each and looking for response times as well as
packet drops.
END
netselect()
{
    $(opt_parse \
        "+quiet q=0 | Don't display progress information, just print the chosen host on stdout." \
        ":count c   | Number of times to ping. Defaults to 10 for multiple hosts or 1 for a single host." \
        "@hosts     | Names or IP address of hosts to test.")

    [[ ${#hosts[@]} -gt 0 ]] || die "must specify hosts to test."
    [[ ${quiet} -eq 1 ]] || eprogress "Finding host with lowest latency $(lval hosts)"

    [[ $# -eq 1 ]] && : ${count:=1} || : ${count:=10}

    declare -a results sorted rows
    local entry

    for h in ${hosts}; do
        entry=$(etimeout -t 5 ping -c${count} -q $h 2>/dev/null | \
            awk '/packet loss/ {loss=$6}
                 /min\/avg\/max/ {
                    split($4,stats,"/")
                    printf("%f|%f|%s|%f", stats[2], stats[4], loss, (stats[2] * stats[4]) * (loss + 1))
                }' || true)

        results+=("${h}|${entry}")
    done

    array_init_nl sorted "$(printf '%s\n' "${results[@]}" | sort -t\| -k5 -n)"
    array_init_nl rows "Server|Latency|Jitter|Loss|Score"

    for entry in ${sorted[@]} ; do
        array_init parts "${entry}" "|"
        array_add_nl rows "${parts[0]}|${parts[1]}|${parts[2]}|${parts[3]}|${parts[4]}"
    done

    local best
    best=$(echo "${sorted[0]}" | cut -d\| -f1)

    if [[ ${quiet} -ne 1 ]] ; then
        eprogress_kill

        ## SHOW ALL RESULTS ##
        einfos "All results:"
        etable ${rows[@]} >&2

        einfos "Best host=[${best}]"
    fi

    echo -en "${best}"
}
