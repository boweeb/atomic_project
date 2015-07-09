#!/usr/bin/bash

#
# Destroy an atomic cluster.
#

HOST_PREFIX="atomic"

for s in "master" "01" "02" "03" "04"; do virsh undefine ${HOST_PREFIX}-${s} --remove-all-storage; done
