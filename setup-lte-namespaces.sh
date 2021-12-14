#!/bin/bash

# Setup networking namespaces for LTE emulation
#
# Namespaces:
#   osnd-moon-cl    : client
#   osnd-moon-clgw  : client gateway
#   root            : emulation network
#   osnd-moon-svgw  : server gateway
#   osnd-moon-sv    : server
#
# Connection overview:
#   root:
#     An Open vSwitch br-lte(root) links the virtual interfaces ue0(root) and eNB0(root) via
#     the physical interfaces em1-4(root). They form the LTE emulation network.
#   client gateway:
#     br-clgw(osnd-moon-clgw), ue2(osnd-moon-clgw), ue1(osnd-moon-clgw) form the client gateway 
#     and connect the application client to the emulation network.
#   server gateway:
#     br-svgw(osnd-moon-svgw), eNB1(osnd-moon-svgw), gw4(osnd-moon-svgw) form the server gateway
#     and connect the application server to the emulation network.
#   client:
#     ue3(osnd-moon-cl) and ue2(osnd-moon-clgw) connect the application client to the client 
#     gateway.
#   server:
#     gw4(osnd-moon-svgw) and gw5(osnd-moon-sv) connect the server gateway to the application 
#     server.

# _moon_setup_add_namespaces
# Create the namespaces and all interfaces within them.
function _moon_setup_add_namespaces() {
    log D "Creating namespaces"

    # Add namespaces
    sudo ip netns add osnd-moon-cl
    sudo ip netns add osnd-moon-clgw
    sudo ip netns add osnd-moon-svgw
    sudo ip netns add osnd-moon-sv

    # Add links
    sudo ip netns exec osnd-moon-cl ip link add ue3 type veth peer name ue2 netns osnd-moon-clgw
    sudo ip link add ue0 type veth peer name ue1
    sudo ip link set ue1 netns osnd-moon-clgw
    sudo ip link add eNB0 type veth peer name eNB1
    sudo ip link set eNB1 netns osnd-moon-svgw
    sudo ip netns exec osnd-moon-sv ip link add gw5 type veth peer name gw4 netns osnd-moon-svgw

    # Add bridges
    sudo ip netns exec osnd-moon-clgw ip link add br-clgw type bridge
    sudo ip netns exec osnd-moon-svgw ip link add br-svgw type bridge

    # Connect links via bridges
    sudo ip netns exec osnd-moon-clgw ip link set dev ue2 master br-clgw
    sudo ip netns exec osnd-moon-clgw ip link set dev ue1 master br-clgw
    sudo ip netns exec osnd-moon-svgw ip link set dev eNB1 master br-svgw
    sudo ip netns exec osnd-moon-svgw ip link set dev gw4 master br-svgw
}

# _moon_setup_ip_config()
function _moon_setup_ip_config() {
    log D "Configuring ip addresses and routes"

    # Configure IP addresses
    sudo ip netns exec osnd-moon-cl ip addr add ${CL_LAN_CLIENT_IP} dev ue3
    sudo ip netns exec osnd-moon-sv ip addr add ${SV_LAN_SERVER_IP} dev gw5

    # Set ifaces up
    sudo ip link set ue0 up
    sudo ip link set eNB0 up
    sudo ip netns exec osnd-moon-cl ip link set ue3 up
    sudo ip netns exec osnd-moon-clgw ip link set ue2 up
    sudo ip netns exec osnd-moon-clgw ip link set ue1 up
    sudo ip netns exec osnd-moon-sv ip link set gw5 up
    sudo ip netns exec osnd-moon-svgw ip link set gw4 up
    sudo ip netns exec osnd-moon-svgw ip link set eNB1 up

    # Set briges up
    sudo ip netns exec osnd-moon-clgw ip link set br-clgw up
    sudo ip netns exec osnd-moon-svgw ip link set br-svgw up

    # Add routes
    sudo ip netns exec osnd-moon-cl ip route add default via ${CL_LAN_CLIENT_IP%%/*}
    sudo ip netns exec osnd-moon-sv ip route add default via ${SV_LAN_SERVER_IP%%/*}
}

# _moon_setup_virtual_switch()
function _moon_setup_virtual_switch() {
    # Add a virtual switch (Open vSwitch)
    sudo ovs-vsctl add-br br-lte

    # Assign ports to the switch
    sudo ovs-vsctl add-port br-lte ue0
    sudo ovs-vsctl add-port br-lte eNB0
    sudo ovs-vsctl add-port br-lte em3
    sudo ovs-vsctl add-port br-lte em4

    # Configure OpenFlow rules to route IPv4 traffic through the LTE emulator
    sudo ovs-ofctl add-flow br-lte in_port=ue0,dl_type=0x0800,actions=output:em3
    sudo ovs-ofctl add-flow br-lte in_port=eNB0,dl_type=0x0800,actions=output:em4
    sudo ovs-ofctl add-flow br-lte in_port=em3,dl_type=0x0800,actions=output:ue0
    sudo ovs-ofctl add-flow br-lte in_port=em4,dl_type=0x0800,actions=output:eNB0

    # Bypass ARP/ICMPv6 traffic
    sudo ovs-ofctl add-flow br-lte arp,in_port=ue0,actions=output:eNB0
    sudo ovs-ofctl add-flow br-lte arp,in_port=eNB0,actions=output:ue0
    sudo ovs-ofctl add-flow br-lte icmp6,in_port=ue0,actions=output:eNB0
    sudo ovs-ofctl add-flow br-lte icmp6,in_port=eNB0,actions=output:ue0
}

# _moon_setup_ground_delay(delay_ms)
function _moon_setup_ground_delay() {
    local delay_ms="$1"

    log D "Configuring ground delay"

    if [ "$delay_ms" -ne "0" ]; then
        sudo ip netns exec osnd-moon-svgw tc qdisc replace dev gw4 handle 1:0 root netem delay ${delay_ms}ms
        sudo ip netns exec osnd-moon-sv tc qdisc replace dev gw5 handle 1:0 root netem delay ${delay_ms}ms
        sudo ip netns exec osnd-moon-clgw tc qdisc replace dev ue2 handle 1:0 root netem delay ${delay_ms}ms
        sudo ip netns exec osnd-moon-cl tc qdisc replace dev ue3 handle 1:0 root netem delay ${delay_ms}ms
    fi
}

# moon_setup_namespaces(delay)
# Create the namespaces and all links within them for the emulation setup.
function moon_setup_namespaces() {
    local delay="${1:-0}"

    _moon_setup_add_namespaces
    _moon_setup_ip_config
    _moon_setup_virtual_switch
    _moon_setup_ground_delay "$delay"
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
    set +a

    moon_setup_namespaces "$@"
fi
