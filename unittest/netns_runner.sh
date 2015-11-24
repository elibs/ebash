#!/bin/bash

if [[ ! -e /sys/class/net/eth0_testns ]] ; then
  echo "eth0_testns doesn't exist"
  ifconfig
  return 1
else
  sleep infinity
fi
