# Module network


## func cidr2netmask

Convert a netmask in CIDR notation to an IPv4 dotted notation (e.g. `24` => `255.255.255.0`). This function takes input in
the form of just a singular number (e.g. `24`) and will echo to standard output the associated IPv4 dotted notation form
of that netmask (e.g. `255.255.255.0`).

See comments in netmask2cidr for a table of all possible netmask/cidr mappings.

From: https://forums.gentoo.org/viewtopic-t-888736-start-0.html

## func export_network_interface_names

Export ethernet device names in the form ETH_1G_0=eth0, etc.

## func fully_qualify_hostname

Convert the provided hostname into a fully qualified hostname.

## func get_network_interfaces

Get list of network interfaces

## func get_network_interfaces_10g

Get list of 10G network interfaces.

## func get_network_interfaces_1g

Get list of 1G network interfaces.

## func get_network_interfaces_with_port

Get list network interfaces with specified "Supported Ports" query.

## func get_network_pci_device


Get the PCI device location for a given ifname

> **_NOTE:_** This is only useful for physical devices, such as eth0, eth1, etc.

```Groff
ARGUMENTS

   ifname
        ifname

```

## func get_network_ports


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

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --listening, -l
         Only include listening ports


ARGUMENTS

   __ports_list
        __ports_list

```

## func get_permanent_mac_address


Get the permanent MAC address for given ifname.

> **_NOTE:_** `ethtool -P` is not reliable on all cards since the firmware has to support it properly. So on Linux we
instead look in __EBASH_SYSFS since this is far more reliable as we're talking direct to the kernel. But on OSX we
instead just use ethtool.

```Groff
ARGUMENTS

   ifname
        ifname

```

## func getbroadcast


Get the broadcast address for the requested interface, if any. It is not an error for a network interface not to have a
broadcast address associated with it (e.g. loopback interfaces). If no broadcast address is set this will just echo an
empty string.

```Groff
ARGUMENTS

   iface
        iface

```

## func getgateway


Gets the default gateway that is currently in use, if any. It is not an error for there to be no gateway set. In that
case this will simply echo an empty string.

```Groff
ARGUMENTS

   iface
        iface

```

## func getipaddress


Get the IPAddress currently bound to the requested interface (if any). It is not an error for an interface to be unbound
so this function will not fail if no IPAddress is set on the interface. Instead it will simply return an empty string.

```Groff
ARGUMENTS

   iface
        iface

```

## func getmtu


Get the MTU that is currently set on a given interface.

```Groff
ARGUMENTS

   iface
        iface

```

## func getnetmask


Get the netmask (IPv4 dotted notation) currently set on the requested interface (if any). It is not an error for an
interface to be unbound so this method will not fail if no Netmask has been set on an interface. Instead it will simply
return an empty string.

```Groff
ARGUMENTS

   iface
        iface

```

## func getsubnet


Compute the subnet given the current IPAddress (ip) and Netmask (nm). If either the provided IPAddress or Netmask is
empty then we cannot compute the subnet. As it's not an error to have no IPAddress or Netmask assigned to an unbound
interface, getsubnet will not fail in this case. The output will be an empty string and it will return 0.

```Groff
ARGUMENTS

   ip
        ?ip

   nm
        ?nm

```

## func getvlans


Get the vlans on a given interface.

```Groff
ARGUMENTS

   iface
        iface

```

## func hostname_to_ip


Convert a given hostname to its corresponding IP Address.

```Groff
ARGUMENTS

   hostname
        hostname

```

## func netmask2cidr

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

## func netselect


Netselect chooses the host that responds most quickly and reliably among a list of specified IP
addresses or hostnames. It does this by pinging each and looking for response times as well as
packet drops.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --count, -c <value>
         Number of times to ping. Defaults to 10 for multiple hosts or 1 for a single host.

   --quiet, -q
         Don't display progress information, just print the chosen host on stdout.


ARGUMENTS

   hosts
         Names or IP address of hosts to test.
```

## func valid_ip


Check if a given input is a syntactically valid IP Address.

```Groff
ARGUMENTS

   ip
        ip

```
