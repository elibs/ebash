#!/usr/bin/env bash

ETEST_netns_create_list_delete()
{
    NS_NAME=namespace_${FUNCNAME}
    trap_add "netns_delete ${NS_NAME}"
    
    # Create the namespace and verify it exists
    netns_create ${NS_NAME}
    assert netns_exists ${NS_NAME}
    
    # Verify the loopback is up in the namespace
    netns_exec ${NS_NAME} ip link | grep "lo:" | assert grep -q "UP"
    
    # Verify the namespace shows up in the list of namespaces
    echo $(netns_list) | assert grep -q ${NS_NAME}

    # Delete and verify it is gone
    netns_delete ${NS_NAME}
    assert_false netns_exists ${NS_NAME}
}

ETEST_netns_with_whitespace_create_list_delete()
{
    NS_NAME="name space ${FUNCNAME}"
    trap_add "netns_delete \"${NS_NAME}\""

    # Create the namespace and verify it exists
    netns_create "${NS_NAME}"
    assert netns_exists "\"${NS_NAME}\""

    # Verify the loopback is up in the namespace
    netns_exec "${NS_NAME}" ip link | grep "lo:" | assert grep -q "UP"

    # Verify the namespace shows up in the list of namespaces
    echo $(netns_list) | assert grep -q "\"${NS_NAME}\""

    # Delete and verify it is gone
    netns_delete "${NS_NAME}"
    assert_false netns_exists "\"${NS_NAME}\""
}

ETEST_netns_exec()
{
    NS_NAME=namespace_${FUNCNAME}
    trap_add "netns_delete ${NS_NAME}"
    
    # Create the namespace and verify it exists
    netns_create ${NS_NAME}
    assert netns_exists ${NS_NAME}
    
    # Look for network interfaces in the namespace; lo should be the only one
    ifaces=$(netns_exec ${NS_NAME} ls /sys/class/net)
    assert_eq "${ifaces}" "lo"
}

ETEST_netns_list()
{
    # Create some namespaces
    NS_NAMES=()
    for i in $(seq 1 5); do
        name=namespace_${FUNCNAME}${i}
        netns_create ${name}
        NS_NAMES+=(${name})
        trap_add "netns_delete ${name}"
    done
    
    # Verify each namespace shows up in the list
    for name in ${NS_NAMES[@]}; do
        echo $(netns_list) | assert grep -q ${name}
    done
}
