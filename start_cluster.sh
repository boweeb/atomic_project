#!/usr/bin/bash

#
# Boot up an atomic cluster.
#

HOST_PREFIX="atomic"

for s in "master" "01" "02" "03" "04"; do virsh start ${HOST_PREFIX}-${s}; done
