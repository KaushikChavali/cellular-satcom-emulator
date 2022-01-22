#!/bin/bash

# osnd_reconfig_namespaces()
# Reconfigure network namespaces for the joint testbed
function osnd_reconfig_namespaces() {

    # Teardown OpenSAND client and server
    sudo ip netns del osnd-cl
    sudo ip netns del osnd-sv

    # Setup dummy namespaces (not used) for sanity
    sudo ip netns add osnd-cl
    sudo ip netns add osnd-sv
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

# osnd_moon_config_routes(route, iw_sv, iw_cl)
# Configure routes from the client to the server according to the selected
# routing strategy, i.e., LTE (default) | SATCOM (SAT) | Multipath (MP).
function osnd_moon_config_routes() {
    local route="$1"
    local iw_sv="$2"
    local iw_cl="$3"

    # Delete routes through the LTE link
    sudo ip netns exec osnd-moon-cl ip route del default via ${CL_LAN_CLIENT_IP_MG%%/*}
    sudo ip netns exec osnd-moon-sv ip route del default via ${SV_LAN_SERVER_IP%%/*}

    if [[ "$route" == "LTE" ]]; then
        # Add route via LTE link
        log D "Setting up routes via MoonGen LTE emulator"
        sudo ip netns exec osnd-moon-cl ip route add ${SV_LAN_NET} via ${CL_LAN_CLIENT_IP_MG%%/*}
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_ROUTER_IP%%/*}
        sudo ip netns exec osnd-moon-sv ip route add default via ${SV_LAN_SERVER_IP%%/*}
    elif [[ "$route" == "SAT" ]]; then
        # Add routes via SATCOM link
        log D "Setting up routes via OpenSAND SATCOM emulator"
        sudo ip netns exec osnd-moon-cl ip route add ${SV_LAN_NET} via ${CL_LAN_ROUTER_IP%%/*}
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_CLIENT_IP_MG%%/*}
        sudo ip netns exec osnd-moon-sv ip route add default via ${SV_LAN_ROUTER_IP%%/*}
    else
        # Configure multi-path routing
        # Ref.: https://multipath-tcp.org/pmwiki.php/Users/ConfigureRouting

        log D "Configuring multi-path routes via LTE and SATCOM links"

        # Enable MPTCP on the machine
        sudo sysctl -wq net.mptcp.mptcp_enabled=1

        # Two different routing tables based on the source-address
        # table 1: LTE (ue3),  table 2: SATCOM (st3)
        sudo ip netns exec osnd-moon-cl ip rule add from ${CL_LAN_CLIENT_IP_MG%%/*} table 1
        sudo ip netns exec osnd-moon-cl ip rule add from ${CL_LAN_CLIENT_IP%%/*} table 2

        # Configure the two different routing tables
        sudo ip netns exec osnd-moon-cl ip route add ${CL_LAN_NET_MG} dev ue3 scope link table 1
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_CLIENT_IP_MG%%/*} dev ue3 table 1

        sudo ip netns exec osnd-moon-cl ip route add ${CL_LAN_NET} dev st3 scope link table 2
        sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_ROUTER_IP%%/*} dev st3 table 2

        # Default route for the selection process of normal traffic
        sudo ip netns exec osnd-moon-cl ip route add default scope global nexthop via ${CL_LAN_CLIENT_IP_MG%%/*} dev ue3

        # Configure route at the server
        sudo ip netns exec osnd-moon-sv ip route add ${CL_LAN_CLIENT_IP%%/*} via ${SV_LAN_ROUTER_IP%%/*} dev gw5
    fi
}

# osnd_moon_setup_ground_delay(delay_ground_ms, delay_cl_sat_ms, delay_cl_lte_ms, delay_sv_ms)
osnd_moon_setup_ground_delay() {
    local delay_ground_ms="$1"
    local delay_cl_sat_ms="$2"
    local delay_cl_lte_ms="$3"
    local delay_sv_ms="$4"

    log D "Configuring satellite ground delay"
    if [ "$delay_ground_ms" -ne "0" ]; then
        sudo ip netns exec osnd-gwp tc qdisc replace dev gw2 handle 1:0 root netem delay ${delay_ground_ms}ms
        sudo ip netns exec osnd-moon-svgw tc qdisc replace dev gw3 handle 1:0 root netem delay ${delay_ground_ms}ms
    fi

    log D "Configuring additional ground delays"
    log D "Configuring client-side ground delays"
    if [ "$delay_cl_sat_ms" -ne "0" ]; then
        sudo ip netns exec osnd-moon-cl tc qdisc replace dev st3 handle 1:0 root netem delay ${delay_cl_sat_ms}ms
        sudo ip netns exec osnd-stp tc qdisc replace dev st2 handle 1:0 root netem delay ${delay_cl_sat_ms}ms
    fi
    if [ "$delay_cl_lte_ms" -ne "0" ]; then
        sudo ip netns exec osnd-moon-cl tc qdisc replace dev ue3 handle 1:0 root netem delay ${delay_cl_lte_ms}ms
        sudo ip netns exec osnd-moon-clgw tc qdisc replace dev ue2 handle 1:0 root netem delay ${delay_cl_lte_ms}ms
    fi

    log D "Configuring server-side ground delays"
    if [ "$delay_sv_ms" -ne "0" ]; then
        sudo ip netns exec osnd-moon-svgw tc qdisc replace dev gw4 handle 1:0 root netem delay ${delay_sv_ms}ms
        sudo ip netns exec osnd-moon-sv tc qdisc replace dev gw5 handle 1:0 root netem delay ${delay_sv_ms}ms
    fi
}

# osnd_moon_build_testbed()
function osnd_moon_build_testbed() {
    local route="LTE"
    local delay_ground="${1:-0}"
    local delay_cl_sat="${2:-0}"
    local delay_cl_lte="${3:-0}"
    local delay_sv="${4:-0}"
    local iw_sv="${4:-10}"
    local iw_cl="${5:-10}"

    osnd_setup_namespaces "$@"
    sleep $CMD_CONFIG_PAUSE

    osnd_reconfig_namespaces
    sleep $CMD_CONFIG_PAUSE

    moon_setup_namespaces "$@"
    sleep $CMD_CONFIG_PAUSE

    osnd_moon_setup_namespaces
    sleep $CMD_CONFIG_PAUSE

    osnd_moon_config_routes "$route" "$iw_sv" "$iw_cl"

    osnd_moon_setup_ground_delay "$delay_ground" "$delay_cl_sat" "$delay_cl_lte" "$delay_sv"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    export OSND_DIR="${SCRIPT_DIR}/quic-opensand-emulation"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    source "${OSND_DIR}/setup-namespaces.sh"
    source "${SCRIPT_DIR}/setup-lte-namespaces.sh"
    set +a

    osnd_moon_build_testbed "$@"
fi
