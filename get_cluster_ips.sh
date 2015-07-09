#!/usr/bin/bash

#
# Destroy an atomic cluster.
#

SUBNET="22"
HOST_PREFIX="atomic"

for x in {1..255}; do echo "$x  ::  $(dig -x 10.62.${SUBNET}.$x +short)"; done | grep ${HOST_PREFIX}
