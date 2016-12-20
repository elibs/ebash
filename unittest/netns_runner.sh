#!/bin/bash

nic=${1:-eth0}

if [[ ! -e /sys/class/net/${nic} ]] ; then
  echo "netns_runner.sh: ERROR: ${nic} doesn't exist"
  echo "Valid nics: $(\ls -m /sys/class/net)"
  exit 1
else
  sleep infinity
fi
