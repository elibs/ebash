#!/usr/bin/env bash

ETEST_ns_create_list_delete()
{
    NS_NAME=namespace_${FUNCNAME}
    trap_add "ns_delete ${NS_NAME}"
    
    # Create the namespace and verify it exists
    ns_create ${NS_NAME}
    assert ns_exists ${NS_NAME}
    
    # Verify the loopback is up in the namespace
    assert ns_exec ${NS_NAME} ip link | grep "lo:" | grep -q "UP"
    
    # Verify the namespace shows up in the list of namespaces
    assert echo $(ns_list) | grep -q ${NS_NAME}

    # Delete and verify it is gone
    ns_delete ${NS_NAME}
    assert ! ns_exists ${NS_NAME}
}

ETEST_ns_exec()
{
    NS_NAME=namespace_${FUNCNAME}
    trap_add "ns_delete ${NS_NAME}"
    
    # Create the namespace and verify it exists
    ns_create ${NS_NAME}
    assert ns_exists ${NS_NAME}
    
    # Look for network interfaces in the namespace; lo should be the only one
    ifaces=$(ns_exec ${NS_NAME} ls /sys/class/net)
    assert [[ "${ifaces}" == "lo" ]]
}

ETEST_ns_list()
{
    # Create some namespaces
    NS_NAMES=()
    for i in $(seq 1 5); do
        name=namespace_${FUNCNAME}${i}
        ns_create ${name}
        NS_NAMES+=(${name})
        trap_add "ns_delete ${name}"
    done
    
    # Verify each namespace shows up in the list
    for name in ${NS_NAMES[@]}; do
        assert echo $(ns_list) | grep -q ${name}
    done
}
