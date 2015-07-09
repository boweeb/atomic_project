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
# DEBUG: (Exec or echo commands)
DEBUG=false

# MANUAL SETTINGS:
HOST_PREFIX="atomic"
NODES=4
SOURCE_IMG_NAME="CentOS-Atomic-Host-7.1.2-GenericCloud.qcow2"
#NET_DEV="wlp8s0"
NET_DEV="br0"
VM_RAM=2048
VM_CPU=2
STORAGE_SIZE="20G"
POOL="default"
POOL_DIR="/var/lib/libvirt/images"
VM_FORMAT="qcow2"
MAC_MASTER="52:54:00:cc:c8:0e"
MAC_NODES=("52:54:00:b4:26:71" "52:54:00:a4:e7:8d" "52:54:00:56:d6:69" "52:54:00:2b:61:0c")
SLEEP_TIME=3

# CALCULATED SETTINGS:
SOURCE_IMG="${PWD}/${SOURCE_IMG_NAME}"
SOURCE_IMG_SIZE_NUM=`qemu-img info ${SOURCE_IMG} --output json | python2 -c 'import sys, json; print(json.load(sys.stdin)["virtual-size"] / (1024**3))'`
SOURCE_IMG_SIZE="${SOURCE_IMG_SIZE_NUM}G"

ISO_DIR="${PWD}/iso"
FULL_PREFIX="${POOL_DIR}/${HOST_PREFIX}"
GOLD_IMG="${FULL_PREFIX}-gold.${VM_FORMAT}"
GOLD_IMG_NAME="${HOST_PREFIX}-gold.${VM_FORMAT}"

# CONFIGURE ARRAYS: (so master is first)
HOST_SEQ[0]="master"
HOST_SEQ_NODES=$(seq -f "%02g" 1 ${NODES})
i=1
for n in $HOST_SEQ_NODES; do
    HOST_SEQ[$i]=$n
    let i=i+1
done

MAC_LIST[0]=$MAC_MASTER
i=1
for n in "${MAC_NODES[@]}"; do
    MAC_LIST[$i]=$n
    let i=i+1
done

# ECHO SETTINGS:
echo -e "Vars:"
echo -e "\tSOURCE_IMG\t= ${SOURCE_IMG}"
echo -e "\tSOURCE_IMG_SIZE\t= ${SOURCE_IMG_SIZE}"
echo -e "\tPOOL\t\t= ${POOL}"
echo -e "\tHOST_PREFIX\t= ${HOST_PREFIX}"
echo -e "\tNODES\t\t= ${NODES}"
echo -e "\t\x1b[31mDEBUG\t\t= \x1b[1m${DEBUG}\x1b[0m\n"


# ##################################################################################################################################
# IMPORT GOLD IMAGE
# ##################################################################################################################################
if [ ! -f ${GOLD_IMG} ]; then
    echo "Copying gold image..."
    CMD_=(\
        "virsh vol-create-as ${POOL} ${GOLD_IMG_NAME} ${SOURCE_IMG_SIZE} --format ${VM_FORMAT}" \
        "virsh vol-upload --pool ${POOL} ${GOLD_IMG_NAME} ${SOURCE_IMG}"\
    )

    for c in "${CMD_[@]}"; do
        if [ "$DEBUG" = true ]; then
            echo -e "\t\x1b[33m${c}\x1b[0m"
        else
            echo -e "\x1b[33m"
            ${c}
            echo -e "\x1b[0m"
        fi
    done
else
    echo -e "\tUse existing gold qcow image..."
fi
echo ""


# ##################################################################################################################################
# CONFIGURE AND LAUNCH VM'S
# ##################################################################################################################################
echo -e "Creating machines..."

echo -e "\tCluster:"
i=0
for h in ${HOST_SEQ[@]}; do
    HOST_NAME=${HOST_PREFIX}-${h}
    echo -e "\t\tNode: ${h}"

    echo -e "\t\t\tFork image from base..."
    CMD_="virsh vol-create-as ${POOL} ${HOST_NAME}.${VM_FORMAT} ${SOURCE_IMG_SIZE} --backing-vol ${GOLD_IMG_NAME} --backing-vol-format ${VM_FORMAT} --format ${VM_FORMAT}"

    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33m$CMD_\x1b[0m"
    else
        echo -e "\x1b[33m"
        $CMD_
        echo -e "\x1b[0m"
    fi

    echo -e "\t\t\tGenerate cloud-init iso..."
    CMD_=(\
        "cd ${HOST_NAME}" \
        "genisoimage -input-charset utf-8 -quiet -output ${ISO_DIR}/${HOST_NAME}-init.iso -volid cidata -joliet -rock user-data meta-data" \
        "virsh vol-create-as ${POOL} ${HOST_NAME}-init.iso 1M --format raw" \
        "virsh vol-upload --pool ${POOL} ${HOST_NAME}-init.iso ${ISO_DIR}/${HOST_NAME}-init.iso" \
        "cd .."\
    )

    for c in "${CMD_[@]}"; do
        if [ "$DEBUG" = true ]; then
            echo -e "\t\t\t\t\x1b[33m${c}\x1b[0m"
        else
            echo -e "\x1b[33m"
            ${c}
            echo -e "\x1b[0m"
        fi
    done

    echo -e "\t\t\tCreate addtional storage..."
    CMD_="virsh vol-create-as ${POOL} ${HOST_NAME}-storage.${VM_FORMAT} ${STORAGE_SIZE} --format ${VM_FORMAT}"

    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33m${CMD_}\x1b[0m"
    else
        echo -e "\x1b[33m"
        ${CMD_}
        echo -e "\x1b[0m"
    fi

    echo -e "\t\t\tInstall VM..."
    # ${MAC_NODE_LIST[${h}-1]}
    CMD_="virt-install \
             --import \
             --name ${HOST_NAME} \
             --os-type=Linux \
             --os-variant=centos7.0 \
             --ram=${VM_RAM} \
             --vcpus=${VM_CPU} \
             --disk vol=${POOL}/${HOST_NAME}.${VM_FORMAT},bus=virtio \
             --disk vol=${POOL}/${HOST_NAME}-storage.${VM_FORMAT},bus=virtio \
             --disk vol=${POOL}/${HOST_NAME}-init.iso,device=cdrom,bus=sata \
             --network bridge=${NET_DEV},mac=${MAC_LIST[$i]} \
             --noautoconsole"

    if [ "$DEBUG" = true ]; then
        echo -e "\t\t\t\t\x1b[33m${CMD_}\x1b[0m"
    else
        echo -e "\x1b[33m"
        ${CMD_}
        echo -e "\x1b[0m"
    fi

    # SUNDRY:
    echo ""
    sleep ${SLEEP_TIME}
    let i=i+1

done


# ##################################################################################################################################
# DONE
# ##################################################################################################################################
echo -e "Done"
