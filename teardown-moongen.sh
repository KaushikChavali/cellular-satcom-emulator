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

# _moon_teardown_moongen_entity(session, binary)
function _moon_teardown_moongen_entity() {
    local session="$1"
    local binary="$2"

    tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo killall ${binary} -q
    tmux -L ${TMUX_SOCKET} kill-session -t ${session} >/dev/null 2>&1
}

# moon_teardown_moongen()
# Teardown all MoonGen entities of the emulation.
function moon_teardown_moongen() {
    log D "Stopping LTE emulation"
    _moon_teardown_moongen_entity "lte-emulation" ${MOONGEN_BIN}
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
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    set +a

    moon_teardown_moongen "$@"
fi
