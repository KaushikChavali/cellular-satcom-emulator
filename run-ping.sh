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

# _osnd_moon_ping_measure(output_dir, run_id)
# Run a single ping measurement and place the results in output_dir.
function _osnd_moon_ping_measure() {
    local output_dir="$1"
    local run_id=$2
    local timeout=110

    log I "Running ping"
    sudo timeout --foreground $timeout ip netns exec osnd-moon-cl ping -n -W 8 -c 10000 -l 100 -i 0.01 ${SV_LAN_SERVER_IP%%/*} >"${output_dir}/$run_id.txt"
    local status=$?

    # Check for error, report if any
    if [ "$status" -ne 0 ]; then
        local emsg="ping exited with status $status"
        if [ "$status" -eq 124 ]; then
            emsg="${emsg} (timeout)"
        fi
        log E "$emsg"
    fi
    log D "ping done"

    return $status
}

# osnd_moon_measure_ping(scenario_config_ref, output_dir, route, run_cnt=1)
# Run all ping measurements and place the results in output_dir.
function osnd_moon_measure_ping() {
    local scenario_config_ref=$1
    local output_dir="$2"
    local route="$3"
    local run_cnt=${4:-1}

    for i in $(seq $run_cnt); do
        log I "Ping run $i/$run_cnt"
        local run_id="ping"

        osnd_moon_setup $scenario_config_ref "$output_dir" "$run_id" "false" "$route"
        sleep $MEASURE_WAIT
        _osnd_moon_ping_measure "$output_dir" "$run_id"
        sleep $MEASURE_GRACE
        osnd_moon_teardown
        sleep $RUN_WAIT
    done

    sleep 3
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }
    declare -A scenario_config

    export SCRIPT_VERSION="manual"
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    export OSND_DIR="${SCRIPT_DIR}/quic-opensand-emulation"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    set +a

    if [[ "$@" ]]; then
        osnd_moon_measure_ping scenario_config "$@"
    else
        osnd_moon_measure_ping scenario_config "."
    fi
fi
