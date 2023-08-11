#!/bin/bash

# cellular-satcom-emulator : Multipath Cellular and Satellite Emulation Testbed
# Copyright (C) 2023 Kaushik Chavali
# 
# This file is part of the cellular-satcom-emulator.
#
# cellular-satcom-emulator is free software: you can redistribute it 
# and/or modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation, either version 3 of 
# the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    set +a
    source "${SCRIPT_DIR}/setup-moongen.sh"
    source "${SCRIPT_DIR}/setup-lte-namespaces.sh"

    moon_setup "$@"
fi
