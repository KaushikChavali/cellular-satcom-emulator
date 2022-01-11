#!/bin/bash

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

# osnd_moon_measure_ping(scenario_config_ref, output_dir, lte=true, run_cnt=1)
# Run all ping measurements and place the results in output_dir.
function osnd_moon_measure_ping() {
    local scenario_config_ref=$1
    local output_dir="$2"
    local lte=${3:-true}
    local run_cnt=${4:-1}

    for i in $(seq $run_cnt); do
        log I "Ping run $i/$run_cnt"
        local run_id="ping_$i"

        osnd_moon_setup $scenario_config_ref "$output_dir" "$run_id" "false" "$lte"
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
