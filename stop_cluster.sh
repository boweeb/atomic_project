#!/usr/bin/bash

#
# Shutdown an atomic cluster.
#

HOST_PREFIX="atomic"

for s in "-master" "01" "02" "03" "04"; do virsh shutdown ${HOST_PREFIX}${s}; done
