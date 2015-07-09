#!/usr/bin/bash

# Generate an atomic cluster.
#
# SOURCE_IMG = qcow2 image (downloaded from http://www.projectatomic.io/download) and in pwd.
# NODES is not confined to '4', changing it really does work.
# Naming Scheme: the (single) master host is <prefix>-master. Nodes are <prefix><two-digit index #>
# The cloud-init files for master are in pwd, not is pwd/master.
#
# NOTE: The 'user-data' files are all hard-linked to the same inode since they'll all be the same.
#
# NEXT STEPS:
# *) You must manually determine and enter the VM's IPs in /etc/hosts
# *) ssh in manually (as user 'centos') to update .ssh/known_hosts
# *) If changing NODES number, update:
#    *) mkdir node in pwd. Hard link user-data and copy/alter meta-data from existing.
#    *) /etc/ansible/hosts
#    *) MAC_NODE_LIST
#    *) [start stop rm]_cluster.sh scripts


# ##################################################################################################################################
# VARS
# ##################################################################################################################################
# MANUAL SETTINGS:
HOST_PREFIX="atomic"
NODES=5
SOURCE_IMG_NAME="CentOS-Atomic-Host-7.1.2-GenericCloud.qcow2"
#NET_DEV="wlp8s0"
NET_DEV="br0"
STORAGE_SIZE=20
POOL_DIR="/var/lib/libvirt/images"
MAC_MASTER="52:54:00:cc:c8:0e"
MAC_NODE_LIST=("52:54:00:b4:26:71" "52:54:00:a4:e7:8d" "52:54:00:56:d6:69" "52:54:00:2b:61:0c")
SLEEP_TIME=1

# CALCULATED SETTINGS:
SOURCE_IMG="${PWD}/${SOURCE_IMG_NAME}"
SOURCE_IMG_SIZE_NUM=`qemu-img info ${SOURCE_IMG} --output json | python2 -c 'import sys, json; print(json.load(sys.stdin)["virtual-size"] / (1024**3))'`
SOURCE_IMG_SIZE="${SOURCE_IMG_SIZE_NUM}G"

ISO_DIR="${PWD}/iso"
FULL_PREFIX="${POOL_DIR}/${HOST_PREFIX}"
GOLD_IMG="${FULL_PREFIX}-gold.qcow2"
GOLD_IMG_NAME="${HOST_PREFIX}-gold.qcow2"

HOST_SEQ[0]="master"
HOST_SEQ_NODES=$(seq -f "%02g" 1 ${NODES})
i=1
for n in $HOST_SEQ_NODES; do
    HOST_SEQ[$i]=$n
    let i=i+1
done
for x in ${HOST_SEQ[@]}; do echo -e "$x"; done

DEBUG=true

# ECHO SETTINGS:
echo -e "Vars:"
echo -e "\tSOURCE_IMG\t= ${SOURCE_IMG}"
echo -e "\tSOURCE_IMG_SIZE\t= ${SOURCE_IMG_SIZE}"
echo -e "\tPOOL_DIR\t= ${POOL_DIR}"
echo -e "\tHOST_PREFIX\t= ${HOST_PREFIX}"
echo -e "\tNODES\t\t= ${NODES}"
echo -e "\t\x1b[31mDEBUG\t\t= \x1b[1m${DEBUG}\x1b[0m\n"


# ##################################################################################################################################
# IMPORT GOLD IMAGE
# ##################################################################################################################################
if [ ! -f ${GOLD_IMG} ]; then
    echo "Copying gold image..."
    if [ "$DEBUG" = true ]; then
        echo -e "\t\x1b[33mvirsh vol-create-as default ${GOLD_IMG_NAME} ${SOURCE_IMG_SIZE} --format qcow2\x1b[0m"
        echo -e "\t\x1b[33mvirsh vol-upload --pool default ${GOLD_IMG_NAME} ${SOURCE_IMG}\x1b[0m"
    else
        echo -e "\x1b[33m"
        virsh vol-create-as default ${GOLD_IMG_NAME} ${SOURCE_IMG_SIZE} --format qcow2
        virsh vol-upload --pool default ${GOLD_IMG_NAME} ${SOURCE_IMG}
        echo -e "\x1b[0m"
    fi
else
    echo -e "\tUse existing gold qcow image..."
fi
# ----------------------------------------------------------------------------------------------------------------------------------
# Deprecating below
# ----------------------------------------------------------------------------------------------------------------------------------
echo -e "Creating machines..."

echo -e "\tMaster:"
echo -e "\t\tFork image from base..."

if [ "$DEBUG" = true ]; then
    #~ echo -e "\t\t\t\x1b[33mqemu-img create -f qcow2 -o backing_file=${GOLD_IMG} ${FULL_PREFIX}-master.qcow2\x1b[0m"
    echo -e "\t\t\t\x1b[33mvirsh vol-create-as default ${HOST_PREFIX}-master.qcow2 ${SOURCE_IMG_SIZE} --backing-vol ${GOLD_IMG_NAME} --backing-vol-format qcow2 --format qcow2\x1b[0m"
else
    echo -e "\x1b[33m"
    #~ qemu-img create -f qcow2 -o backing_file=${GOLD_IMG} ${FULL_PREFIX}-master.qcow2
    virsh vol-create-as default ${HOST_PREFIX}-master.qcow2 ${SOURCE_IMG_SIZE} --backing-vol ${GOLD_IMG_NAME} --backing-vol-format qcow2 --format qcow2
    echo -e "\x1b[0m"
fi

if [ ! -f ${FULL_PREFIX}-master-init.iso ]; then
    echo -e "\t\tGenerate cloud-init iso..."
    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\tcd master"
        echo -e "\t\t\t\x1b[33mgenisoimage -input-charset utf-8 -quiet -output ${ISO_DIR}/${HOST_PREFIX}-master-init.iso -volid cidata -joliet -rock user-data meta-data\x1b[0m"
        echo -e "\t\t\t\x1b[33mvirsh vol-create-as default ${HOST_PREFIX}-master-init.iso 1M --format raw\x1b[0m"
        echo -e "\t\t\t\x1b[33mvirsh vol-upload --pool default ${HOST_PREFIX}-master-init.iso ${ISO_DIR}/${HOST_PREFIX}-master-init.iso\x1b[0m"
        echo -e "\t\t\tcd .."
    else
        cd master
        echo -e "\x1b[33m"
        genisoimage -input-charset utf-8 -quiet -output ${ISO_DIR}/${HOST_PREFIX}-master-init.iso -volid cidata -joliet -rock user-data meta-data
        virsh vol-create-as default ${HOST_PREFIX}-master-init.iso 1M --format raw
        virsh vol-upload --pool default ${HOST_PREFIX}-master-init.iso ${ISO_DIR}/${HOST_PREFIX}-master-init.iso
        echo -e "\x1b[0m"
        cd ..
    fi
else
    echo -e "\t\tUse existing cloud-init iso..."
fi

echo -e "\t\tInstall VM..."
if [ "$DEBUG" = true ]; then
    echo -e "\x1b[33m"
    echo -e "\t\t\tvirsh vol-create-as default ${HOST_PREFIX}-master-storage.qcow2 ${STORAGE_SIZE} --format qcow2"
    echo -e "\t\t\tvirt-install \\"
    echo -e "\t\t\t\t--import \\"
    echo -e "\t\t\t\t--name \"${HOST_PREFIX}-master\" \\"
    echo -e "\t\t\t\t--description \"Atomic Cluster Master\" \\"
    echo -e "\t\t\t\t--os-type=Linux \\"
    echo -e "\t\t\t\t--os-variant=centos7.0 \\"
    echo -e "\t\t\t\t--ram=2048 \\"
    echo -e "\t\t\t\t--vcpus=2 \\"
    echo -e "\t\t\t\t--disk vol=default/${HOST_PREFIX}-master.qcow2,bus=virtio \\"
    echo -e "\t\t\t\t--disk vol=default/${HOST_PREFIX}-master-storage.qcow2,bus=virtio \\"
    echo -e "\t\t\t\t--disk vol=default/${HOST_PREFIX}-master-init.iso,device=cdrom,bus=sata \\"
    echo -e "\t\t\t\t--network bridge=br0,mac=${MAC_MASTER} \\"
    echo -e "\t\t\t\t--noautoconsole"
    echo -e "\x1b[0m\n"
else
    echo -e "\x1b[33m"
    virsh vol-create-as default ${HOST_PREFIX}-master-storage.qcow2 ${STORAGE_SIZE} --format qcow2
    virt-install \
        --import \
        --name "${HOST_PREFIX}-master" \
        --description "Atomic Cluster Master" \
        --os-type=Linux \
        --os-variant=centos7.0 \
        --ram=2048 \
        --vcpus=2 \
        --disk vol=default/${HOST_PREFIX}-master.qcow2,bus=virtio \
        --disk vol=default/${HOST_PREFIX}-master-storage.qcow2,bus=virtio \
        --disk vol=default/${HOST_PREFIX}-master-init.iso,device=cdrom,bus=sata \
        --network bridge=${NET_DEV},mac=${MAC_MASTER} \
        --noautoconsole
    echo -e "\x1b[0m\n"
fi


# ##################################################################################################################################
# CONFIGURE AND LAUNCH VM'S
# ##################################################################################################################################
echo -e "\tCluster:"
for i in ${HOST_SEQ[@]}; do
    echo -e "\t\tNode: ${i}"

    echo -e "\t\t\tFork image from base..."
    CMD_="virsh vol-create-as default ${HOST_PREFIX}-master.qcow2 ${SOURCE_IMG_SIZE} --backing-vol ${GOLD_IMG_NAME} --backing-vol-format qcow2 --format qcow2"

    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33m$CMD_\x1b[0m"
    else
        echo -e "\x1b[33m"
        $CMD_
        echo -e "\x1b[0m"
    fi
    echo -e "\t\t\tGenerate cloud-init iso..."
    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33mcd node${i}\x1b[0m"
        echo -e "\t\t\t\t\x1b[33mgenisoimage -input-charset utf-8 -quiet -output ${FULL_PREFIX}${i}-init.iso -volid cidata -joliet -rock user-data meta-data\x1b[0m"
        echo -e "\t\t\t\t\x1b[33mcd ..\x1b[0m"
    else
        cd node${i}
        echo -e "\x1b[33m"
        genisoimage -input-charset utf-8 -quiet -output ${FULL_PREFIX}${i}-init.iso -volid cidata -joliet -rock user-data meta-data
        echo -e "\x1b[0m"
        cd ..
    fi
    echo -e "\t\t\tInstall VM..."
    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33mvirt-install \\"
        echo -e "\t\t\t\t|\t--import \\"
        echo -e "\t\t\t\t|\t--name \"${HOST_PREFIX}${i}\" \\"
        echo -e "\t\t\t\t|\t--description \"Atomic Node ${i}\" \\"
        echo -e "\t\t\t\t|\t--os-type=Linux \\"
        echo -e "\t\t\t\t|\t--os-variant=centos7.0 \\"
        echo -e "\t\t\t\t|\t--ram=2048 \\"
        echo -e "\t\t\t\t|\t--vcpus=2 \\"
        echo -e "\t\t\t\t|\t--disk path=${FULL_PREFIX}${i}.qcow2,format=qcow2,bus=virtio \\"
        echo -e "\t\t\t\t|\t--disk ${FULL_PREFIX}${i}-init.iso,device=cdrom \\"
        echo -e "\t\t\t\t|\t--network bridge=br0,mac=${MAC_NODE_LIST[${i}-1]} \\"
        echo -e "\t\t\t\t|\t--noautoconsole\x1b[0m"
    else
        echo -e "\x1b[33m"
        virt-install \
            --import \
            --name "${HOST_PREFIX}{i}" \
            --description "Atomic Node ${i}" \
            --os-type=Linux \
            --os-variant=centos7.0 \
            --ram=2048 \
            --vcpus=2 \
            --disk path=${FULL_PREFIX}${i}.qcow2,format=qcow2,bus=virtio \
            --disk ${FULL_PREFIX}${i}-init.iso,device=cdrom \
            --network bridge=br0,mac=${MAC_NODE_LIST[${i}-1]} \
            --noautoconsole
        echo -e "\x1b[0m"
    fi
    sleep ${SLEEP_TIME}
done


# ##################################################################################################################################
# DONE
# ##################################################################################################################################
echo -e "Done"
