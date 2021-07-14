# Module netns


## func netns_check_pack


Ensure that the minimum parameters to set up a namespace are present in the pack and that the
parameters meet some minimum criteria in form and/or length

```Groff
ARGUMENTS

   netns_args_packname
         Name of variable containing netns information. (Was created by netns init with a name
         you chose)

```

## func netns_chroot_exec


Run a command in a netns chroot that already exists.

```Groff
ARGUMENTS

   netns_args_packname
         Name of variable containing netns information. (Was created by netns init with a name
         you chose)

   chroot_root
         Existing chroot to run within.

   command
         Command and arguments.
```

## func netns_create


Idempotent create a network namespace.

```Groff
ARGUMENTS

   ns_name
        ns_name

```

## func netns_delete


Idempotent delete a network namespace.

```Groff
ARGUMENTS

   ns_name
        ns_name

```

## func netns_exec


Execute a command in the given network namespace.

```Groff
ARGUMENTS

   ns_name
        ns_name

```

## func netns_exists


Check if a network namespace exists.

```Groff
ARGUMENTS

   ns_name
        ns_name

```

## func netns_init


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

```Groff
ARGUMENTS

   netns_args_packname
         Name of variable that will be used to hold this netns's information.

   netns_options
         Network namespace options to use in form option=value
```

## func netns_list

Get a list of network namespaces.

## func netns_supported


Check which network namespace features are supported.

```Groff
ARGUMENTS

   area
        ?area=all

```
