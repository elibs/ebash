#!/usr/bin/env bash
#
# Copyright 2011-2016, SolidFire, Inc. All rights reserved.
#

#-----------------------------------------------------------------------------
# NETWORKING FUNCTIONS
#-----------------------------------------------------------------------------
valid_ip()
{
    $(declare_args ip)
    local stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        array_init ip "${ip}" "."
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

hostname_to_ip()
{
    $(declare_args hostname)

    local output hostrc ip
    output="$(host ${hostname} | grep ' has address ' || true)"
    hostrc=$?
    edebug "hostname_to_ip $(lval hostname output)"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    ip=$(echo ${output} | awk '{print $4}')

    valid_ip ${ip} || { ewarn "Resolved ${hostname} into invalid ip address ${ip}." ; return 1 ; }

    echo ${ip}
    return 0
}

fully_qualify_hostname()
{
    local hostname=${1,,}
    argcheck hostname

    local output hostrc fqhostname
    output=$(host ${hostname})
    hostrc=$?
    edebug "fully_qualify_hostname: hostname=${hostname} output=${output}"
    [[ ${hostrc} -eq 0 ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }

    [[ ${output} =~ " has address " ]] || { ewarn "Unable to resolve ${hostname}." ; return 1 ; }
    fqhostname=$(echo ${output} | awk '{print $1}')
    fqhostname=${fqhostname,,}

    [[ ${fqhostname} =~ ${hostname} ]] || { ewarn "Invalid fully qualified name ${fqhostname} from ${hostname}." ; return 1 ; }

    echo ${fqhostname}
    return 0
}

[[ ${__BU_OS} == Linux ]] || return 0

#-----------------------------------------------------------------------------
# Linux-specific networking functions
#-----------------------------------------------------------------------------

# Get the IPAddress currently bound to the requested interface (if any). It is
# not an error for an interface to be unbound so this function will not fail if
# no IPAddress is set on the interface. Instead it will simply return an empty
# string.
getipaddress()
{
    $(declare_args iface)
    ip addr show "${iface}" | awk '/inet [0-9.\/]+ .*'${iface}'$/ { split($2, arr, "/"); print arr[1] }' || true
}

# Get the netmask (IPv4 dotted notation) currently set on the requested
# interface (if any). It is not an error for an interface to be unbound so this
# method will not fail if no Netmask has been set on an interface. Instead it
# will simply return an empty string.
getnetmask()
{
    $(declare_args iface)
    local cidr=$(ip addr show "${iface}" | awk '/inet [0-9.\/]+ .*'${iface}'$/ { split($2, arr, "/"); print arr[2] }' || true)
    [[ -z "${cidr}" ]] && return 0

    cidr2netmask "${cidr}"
}

# Convert a netmask in IPv4 dotted notation into CIDR notation (e.g 255.255.255.0 => 24).
# Below is the official chart of all possible valid Netmasks in quad-dotted decimal notation
# with the associated CIDR value:
#
# { "255.255.255.255", 32 }, { "255.255.255.254", 31 }, { "255.255.255.252", 30 }, { "255.255.255.248", 29 },
# { "255.255.255.240", 28 }, { "255.255.255.224", 27 }, { "255.255.255.192", 26 }, { "255.255.255.128", 25 },
# { "255.255.255.0",   24 }, { "255.255.254.0",   23 }, { "255.255.252.0",   22 }, { "255.255.248.0",   21 },
# { "255.255.240.0",   20 }, { "255.255.224.0",   19 }, { "255.255.192.0",   18 }, { "255.255.128.0",   17 },
# { "255.255.0.0",     16 }, { "255.254.0.0",     15 }, { "255.252.0.0",     14 }, { "255.248.0.0",     13 },
# { "255.240.0.0",     12 }, { "255.224.0.0",     11 }, { "255.192.0.0",     10 }, { "255.128.0.0",      9 },
# { "255.0.0.0",        8 }, { "254.0.0.0",        7 }, { "252.0.0.0",        6 }, { "248.0.0.0",        5 },
# { "240.0.0.0",        4 }, { "224.0.0.0",        3 }, { "192.0.0.0",        2 }, { "128.0.0.0",        1 },
#
# From: https://forums.gentoo.org/viewtopic-t-888736-start-0.html
netmask2cidr ()
{
    # Assumes there's no "255." after a non-255 byte in the mask 
    set -- 0^^^128^192^224^240^248^252^254^ ${#1} ${1##*255.} 
    set -- $(( ($2 - ${#3})*2 )) ${1%%${3%%.*}*} 
    echo $(( $1 + (${#2}/4) ))
}

# Convert a netmask in CIDR notation to an IPv4 dotted notation (e.g. 24 => 255.255.255.0).
# This function takes input in the form of just a singular number (e.g. 24) and will echo to
# standard output the associated IPv4 dotted notation form of that netmask (e.g. 255.255.255.0).
#
# See comments in netmask2cidr for a table of all possible netmask/cidr mappings.
#
# From: https://forums.gentoo.org/viewtopic-t-888736-start-0.html
cidr2netmask ()
{
    # Number of args to shift, 255..255, first non-255 byte, zeroes
    set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
    [ $1 -gt 1 ] && shift $1 || shift
    echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Get the broadcast address for the requested interface, if any. It is not an
# error for a network interface not to have a broadcast address associated with
# it (e.g. loopback interfaces). If no broadcast address is set this will just
# echo an empty string.
getbroadcast()
{
    $(declare_args iface)
    ip addr show "${iface}" | awk '/inet [0-9.\/]+ brd .*'${iface}'$/ { print $4 }' || true
}

# Gets the default gateway that is currently in use, if any. It is not an
# error for there to be no gateway set. In that case this will simply echo an
# empty string.
getgateway()
{
    route -n | awk '/UG[ \t]/ { print $2 }' || true
}

# Compute the subnet given the current IPAddress (ip) and Netmask (nm). If either
# the provided IPAddress or Netmask is empty then we cannot compute the subnet.
# As it's not an error to have no IPAddress or Netmask assigned to an unbound
# interface, getsubnet will not fail in this case. The output will be an empty
# string and it will return 0.
getsubnet()
{
    $(declare_args ?ip ?nm)
    [[ -z "${ip}" || -z "${nm}" ]] && return 0

    IFS=. read -r i1 i2 i3 i4 <<< "${ip}"
    IFS=. read -r m1 m2 m3 m4 <<< "${nm}"

    printf "%d.%d.%d.%d" "$((i1 & m1))" "$(($i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

# Get the MTU that is currently set on a given interface.
getmtu()
{
    $(declare_args iface)
    ip addr show "${iface}" | grep -Po 'mtu \K[\d.]+'
}

# Get list of network interfaces
get_network_interfaces()
{
    ls -1 /sys/class/net | egrep -v '(bonding_masters|Bond)' | tr '\n' ' ' || true
}

# Get list network interfaces with specified "Supported Ports" query.
get_network_interfaces_with_port()
{
    local query="$1"
    local ifname port
    local results=()

    for ifname in $(get_network_interfaces); do
        port=$(ethtool ${ifname} | grep "Supported ports:" || true)
        [[ ${port} =~ "${query}" ]] && results+=( ${ifname} )
    done

    echo -n "${results[@]}"
}

# Get list of 1G network interfaces
get_network_interfaces_1g()
{
    get_network_interfaces_with_port "TP"
}

# Get list of 10G network interfaces
get_network_interfaces_10g()
{
    get_network_interfaces_with_port "FIBRE"
}

# Get the permanent MAC address for given ifname.
# NOTE: Do NOT use ethtool -P for this as that doesn't reliably
#       work on all cards since the firmware has to support it properly.
get_permanent_mac_address()
{
    $(declare_args ifname)

    if [[ -e /sys/class/net/${ifname}/master ]]; then
        sed -n "/Slave Interface: ${ifname}/,/^$/p" /proc/net/bonding/$(basename $(readlink -f /sys/class/net/${ifname}/master)) \
            | grep "Permanent HW addr" \
            | sed -e "s/Permanent HW addr: //"
    else
        cat /sys/class/net/${ifname}/address
    fi
}

# Get the PCI device location for a given ifname
# NOTE: This is only useful for physical devices, such as eth0, eth1, etc.
get_network_pci_device()
{
    $(declare_args ifname)

    (cd /sys/class/net/${ifname}/device; basename $(pwd -P))
}

# Export ethernet device names in the form ETH_1G_0=eth0, etc.
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

# Get a list of the active network ports on this machine. The result is returned as an array of packs stored in the
# variable passed to the function.
#
# Options:
#  -l Only include listening ports
#
# For example:
# declare -A ports
# get_listening_ports ports
# einfo $(lval +ports[5])
# >> ports[5]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="0.0.0.0" [local_port]="22" [remote_addr]="0.0.0.0" [remote_port]="0" [state]="LISTEN" [pid]="9278" [prog]="sshd" )
# einfo $(lval +ports[42])
# ports[42]=([proto]="tcp" [recvq]="0" [sendq]="0" [local_addr]="172.17.5.208" [local_port]="48899" [remote_addr]="173.194.115.70" [remote_port]="443" [state]="ESTABLISHED" [pid]="28073" [prog]="chrome" )
#
get_network_ports()
{
    $(declare_opts "-listening l | Only include listening ports")
    $(declare_args __ports_list)

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
