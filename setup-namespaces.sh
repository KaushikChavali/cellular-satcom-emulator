#!/bin/bash

# osnd_reconfig_namespaces()
# Reconfigure network namespaces for the joint testbed
function osnd_reconfig_namespaces() {

    # Teardown OpenSAND client and server
    sudo ip netns del osnd-cl
    sudo ip netns del osnd-sv
}

# osnd_moon_setup_namespaces()
# Build the joint testbed
function osnd_moon_setup_namespaces() {
    # Add links and bridges via OpenSAND network
    sudo ip netns exec osnd-moon-cl ip link add st3 type veth peer name st2 netns osnd-stp
    sudo ip netns exec osnd-moon-svgw ip link add gw3 type veth peer name gw2 netns osnd-gwp

    # Connect links via bridges
    sudo ip netns exec osnd-moon-svgw ip link set gw3 master br-svgw

    # Configure IP addresses
    sudo ip netns exec osnd-moon-cl ip addr add ${CL_LAN_CLIENT_IP} dev st3
    sudo ip netns exec osnd-stp ip addr add ${CL_LAN_ROUTER_IP} dev st2
    sudo ip netns exec osnd-gwp ip addr add ${SV_LAN_ROUTER_IP} dev gw2
    sudo ip netns exec osnd-moon-svgw ip addr add ${SV_LAN_SERVER_IP} dev gw3

    # Set ifaces up
    sudo ip netns exec osnd-moon-cl ip link set st3 up
    sudo ip netns exec osnd-stp ip link set st2 up
    sudo ip netns exec osnd-gwp ip link set gw2 up
    sudo ip netns exec osnd-moon-svgw ip link set gw3 up
}

# osnd_moon_config_routes(lte, satcom)
# Configure routes from the client to the server based on the chosen
# path via LTE or SATCOM link.
function osnd_moon_config_routes() {
    local lte="$1"

    # Delete route through the LTE link
    sudo ip netns exec osnd-moon-cl ip route del default via ${CL_LAN_CLIENT_IP_MG%%/*}
    sudo ip netns exec osnd-moon-sv ip route del default via ${SV_LAN_SERVER_IP%%/*}

    if [[ "$lte" == true ]]; then
        # Add route via LTE link
        log D "Setting up routes via MoonGen LTE emulator"
        sudo ip netns exec osnd-moon-cl ip route add ${SV_LAN_NET} via ${CL_LAN_CLIENT_IP_MG%%/*}
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_ROUTER_IP%%/*}
        sudo ip netns exec osnd-moon-sv ip route add default via ${SV_LAN_SERVER_IP%%/*}
    else
        # Add routes via SATCOM link
        log D "Setting up routes via OpenSAND SATCOM emulator"
        sudo ip netns exec osnd-moon-cl ip route add ${SV_LAN_NET} via ${CL_LAN_ROUTER_IP%%/*}
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_CLIENT_IP_MG%%/*}
        sudo ip netns exec osnd-moon-sv ip route add default via ${SV_LAN_ROUTER_IP%%/*}
    fi
}

# osnd_moon_build_testbed()
function osnd_moon_build_testbed() {
    local lte="true"

    osnd_setup_namespaces "$@"
    sleep $CMD_CONFIG_PAUSE

    osnd_reconfig_namespaces
    sleep $CMD_CONFIG_PAUSE

    moon_setup_namespaces "$@"
    sleep $CMD_CONFIG_PAUSE

    osnd_moon_setup_namespaces
    sleep $CMD_CONFIG_PAUSE

    osnd_moon_config_routes "$lte"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

    set -a
    source "${SCRIPT_DIR}/config/lte-config.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/env.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/setup-namespaces.sh"
    source "${SCRIPT_DIR}/setup-lte-namespaces.sh"
    set +a

    osnd_moon_build_testbed "$@"
fi
