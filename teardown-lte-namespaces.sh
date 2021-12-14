#!/bin/bash

# moon_teardown_namespaces()
# Remove all namespaces and the components within them.
function moon_teardown_namespaces() {
    sudo ip netns del osnd-moon-cl
    sudo ip netns del osnd-moon-clgw
    sudo ip netns del osnd-moon-sv
    sudo ip netns del osnd-moon-svgw

    # Delete bridge and all its ports
    sudo ovs-vsctl del-br br-lte
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    moon_teardown_namespaces "$@"
fi
