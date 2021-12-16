#!/bin/bash

# _moon_prime_env(seconds)
# Prime the environment with a few pings
function _moon_prime_env() {
    local seconds=$1

    log D "Priming environment"
    sudo timeout --foreground $(echo "$seconds + 1" | bc -l) ip netns exec osnd-moon-cl \
        ping -n -W 8 -c $(echo "$seconds * 100" | bc -l) -l 100 -i 0.01 ${SV_LAN_SERVER_IP%%/*} >/dev/null
}

# _moon_capture(output_dir, run_id, pep, capture_nr)
# Start capturing packets
function _moon_capture() {
    local output_dir="$1"
    local run_id="$2"
    local capture="$3"

    log D "Starting tcpdump"

    # Server
    tmux -L ${TMUX_SOCKET} new-session -s tcpdump-sv -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-sv "tcpdump -i gw5 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_server_gw5.eth'" Enter

    # Client
    tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i ue3 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_client_ue3.eth'" Enter
}

# moon_setup()
# Setup the entire emulation environment.
function moon_setup() {
    local output_dir="${1:-./out}"
    local run_id="${2:-manual}"
    local prime="${3:-4}"
    local dump="${4:-65535}"

    log I "Setting up emulation environment"

    moon_setup_namespaces
    sleep 1
    moon_setup_moongen
    sleep 10
    if [ "$dump" -gt 0 ]; then
        _moon_capture "$output_dir" "$run_id" "$dump"
    fi

    if (($(echo "$prime > 0" | bc -l))); then
        _moon_prime_env $prime
    fi

    log D "Environment set up"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_VERSION="manual"
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    set -a
    source "${SCRIPT_DIR}/config/lte-config.sh"
    set +a
    source "${SCRIPT_DIR}/setup-moongen.sh"
    source "${SCRIPT_DIR}/setup-lte-namespaces.sh"

    moon_setup "$@"
fi
