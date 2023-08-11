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

# _disable_mptcp_protocol()
function _disable_mptcp_protocol() {
    # Disable MPTCP on the machine
    sudo sysctl -wq net.mptcp.mptcp_enabled=0
}

# _osnd_moon_teardown_capture()
# Stop capturing packets
function _osnd_moon_teardown_capture() {
    local logged=false

    for entity in cl st gw sv; do
        local session="tcpdump-${entity}"
        tmux -L ${TMUX_SOCKET} has-session -t ${session} >/dev/null 2>&1
        if [ "$?" -gt 0 ]; then
            if [[ "$logged" == false ]]; then
                log D "Stopping tcpdump"
                logged=true
            fi

            log D "Stopping $session"
            tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-c
            sleep $CMD_SHUTDOWN_WAIT
            tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-d
            sleep $CMD_SHUTDOWN_WAIT
            tmux -L ${TMUX_SOCKET} kill-session -t ${session} >/dev/null 2>&1
        fi
    done
}

# osnd_moon_teardown()
# Teardown the entire emulation environment.
function osnd_moon_teardown() {
    local mp_prot="${scenario_config_ref['mp_prot']:-MPTCP}"

    log I "Tearing down emulation environment"
    osnd_teardown_opensand
    sleep $CMD_SHUTDOWN_WAIT
    moon_teardown_moongen
    sleep $CMD_SHUTDOWN_WAIT
    # _osnd_moon_teardown_capture
    osnd_teardown_namespaces
    moon_teardown_namespaces
    if [[ "$mp_prot" == "MPTCP" ]]; then
        _disable_mptcp_protocol
    fi
    log D "Environment teared down"
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
    export OSND_DIR="${SCRIPT_DIR}/quic-opensand-emulation"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    source "${OSND_DIR}/teardown-opensand.sh"
    source "${OSND_DIR}/teardown-namespaces.sh"
    source "${SCRIPT_DIR}/teardown-moongen.sh"
    source "${SCRIPT_DIR}/teardown-lte-namespaces.sh"
    set +a

    osnd_moon_teardown "$@"

    # Ensure all tmux sessions are closed
    tmux -L ${TMUX_SOCKET} kill-server &>/dev/null

    if [ -e "$OSND_TMP" ]; then
        rm -rf "$OSND_TMP"
    fi
fi
