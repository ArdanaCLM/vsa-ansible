#!/bin/bash
#
# (c) Copyright 2015 Hewlett Packard Enterprise Development LP
# (c) Copyright 2017 SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
set -eu
set -o pipefail

die() {
    echo "$1" >&2
    exit 1
}

make_bridge() {
    ovs-vsctl -- --may-exist add-br "${BRIDGE_NAME}"
    ip link set dev ${BRIDGE_NAME} up

    # Obtain current routes for the interface.
    ROUTES=$(ip route list | grep ${BRIDGE_INTERFACE} || true)
    CFG=$(ip addr show ${BRIDGE_INTERFACE} | awk '/inet / {$1="";$(NF)=""; print $0}' || true)
    CFG=$(echo "$CFG" |  sed  s/dynamic//)
    if [ -z "$CFG" ] ; then
        die "Error: BRIDGE_INTERFACE:${BRIDGE_INTERFACE} has no assigned IP address"
    fi

    ovs-vsctl -- --may-exist add-port ${BRIDGE_NAME} ${BRIDGE_INTERFACE}

    # Remap the current addresses to the bridge.
    if [[ -n "${CFG}" ]]; then
        SAVEIFS=$IFS;
        IFS=$(echo -en "\n\b");
        for item in ${CFG} ; do
            eval ip addr del dev ${BRIDGE_INTERFACE} ${item}
            eval ip addr add dev ${BRIDGE_NAME} ${item}
        done
        IFS=$SAVEIFS
    fi

    # Ensure we only set up the missing routes on the bridge.
    ROUTES=${ROUTES//${BRIDGE_INTERFACE}/${BRIDGE_NAME}}
    ROUTES_NEW=$( ( echo "${ROUTES}"; ip route list |
                            awk -v dev="${BRIDGE_NAME}" '$0 ~ dev {print $0}' ) | sort | uniq -u )

    SAVEIFS=$IFS;
    IFS=$(echo -en "\n\b");
    for LINE in ${ROUTES_NEW}; do
        eval ip route replace $LINE
    done
    IFS=$SAVEIFS
}

BRIDGE_INTERFACE=$1
BRIDGE_NAME=${2:-'vsa-bridge'}

make_bridge;
