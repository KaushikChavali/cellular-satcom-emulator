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

# _osnd_moon_quic_measure(output_dir, run_id, cc, tbs, qbs, ubs, iw, max_ack_delay, first_ack_freq_packet_number, ack_freq_cwnd_fraction, qlog_file, measure_secs, timeout, server_ip)
function _osnd_moon_quic_measure() {
    local output_dir="$1"
    local run_id="$2"
    local cc="$3"
    local tbs="$4"
    local qbs="$5"
    local ubs="$6"
    local iw="$7"
    local max_ack_delay="$8"
    local first_ack_freq_packet_number="$9"
    local ack_freq_cwnd_fraction="${10}"
    local qlog_file_client="${11}"
    local measure_secs="${12}"
    local timeout="${13}"
    local server_ip="${14}"

    local measure_opt="-t ${measure_secs}"
    if [[ "$measure_secs" -lt 0 ]]; then
        measure_opt="-e"
    fi

    log I "Running qperf client"
    sudo timeout --foreground $timeout ip netns exec osnd-moon-cl ${QPERF_BIN} -c ${server_ip} -p 18080 --cc ${cc} -i ${REPORT_INTERVAL} -b ${tbs} -q ${qbs} -u ${ubs} -w ${iw} --events ${qlog_file_client} --max-ack-delay ${max_ack_delay} --first-ack-freq-packet-number ${first_ack_freq_packet_number} --ack-freq-cwnd-fraction ${ack_freq_cwnd_fraction} $measure_opt --print-raw >"${output_dir}/${run_id}_client.txt"
    local status=$?

    # Check for error, report if any
    if [ "$status" -ne 0 ]; then
        local emsg="qperf exited with status $status"
        if [ "$status" -eq 124 ]; then
            emsg="${emsg} (timeout)"
        fi
        log E "$emsg"
    fi
    log D "qperf done"

    return $status
}

# _osnd_moon_quic_server_start(output_dir, run_id, cc, tbs, qbs, ubs, iw, max_ack_delay, first_ack_freq_packet_number, ack_freq_cwnd_fraction, qlog_file)
function _osnd_moon_quic_server_start() {
    local output_dir="$1"
    local run_id="$2"
    local cc="$3"
    local tbs="$4"
    local qbs="$5"
    local ubs="$6"
    local iw="$7"
    local max_ack_delay="$8"
    local first_ack_freq_packet_number="$9"
    local ack_freq_cwnd_fraction="${10}"
    local qlog_file_server="${11}"

    log I "Starting qperf server"
    sudo ip netns exec osnd-moon-sv killall qperf -q
    tmux -L ${TMUX_SOCKET} new-session -s qperf-server -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-server \
        "${QPERF_BIN} -s --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc} -i ${REPORT_INTERVAL} -b ${tbs} -q ${qbs} -u ${ubs} -w ${iw} --events ${qlog_file_server} --max-ack-delay ${max_ack_delay} --first-ack-freq-packet-number ${first_ack_freq_packet_number} --ack-freq-cwnd-fraction ${ack_freq_cwnd_fraction} --listen-addr ${SV_LAN_SERVER_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_server.txt' 2> >(awk '{print(\"E\", \"qperf-server:\", \$0)}' > ${OSND_TMP}/logging)" \
        Enter
}

# _osnd_moon_quic_server_stop()
function _osnd_moon_quic_server_stop() {
    log I "Stopping qperf server"

    tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-server C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-moon-sv killall $(basename $QPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t qperf-server >/dev/null 2>&1
}

# _osnd_quic_proxies_start(output_dir, run_id, cc_gw, cc_st, tbs_gw, tbs_st, qbs_gw, qbs_st, ubs_gw, ubs_st, iw_gw, iw_st, max_ack_delay, first_ack_freq_packet_number, ack_freq_cwnd_fraction, use_alpn, wait_for_svr)
function _osnd_quic_proxies_start() {
    local output_dir="$1"
    local run_id="$2"
    local cc_gw="$3"
    local cc_st="$4"
    local tbs_gw="$5"
    local tbs_st="$6"
    local qbs_gw="$7"
    local qbs_st="$8"
    local ubs_gw="$9"
    local ubs_st="${10}"
    local iw_gw="${11}"
    local iw_st="${12}"
    local max_ack_delay="${13}"
    local first_ack_freq_packet_number="${14}"
    local ack_freq_cwnd_fraction="${15}"
    local use_alpn="${16:-false}"
    local wait_for_svr="${17:-false}"

    local QPERF_BIN_LOCAL="${QPERF_BIN}"
    if [[ "$use_alpn" == true ]]; then
        QPERF_BIN_LOCAL="${QPERF_BIN_LOCAL} --alpn h3"
    fi
    if [[ "$wait_for_svr" == true ]]; then
        QPERF_BIN_LOCAL="${QPERF_BIN_LOCAL} --wait-for-svr"
    fi

    log I "Starting qperf proxies"

    # Gateway proxy
    log D "Starting gateway proxy"
    tmux -L ${TMUX_SOCKET} new-session -s qperf-proxy-gw -d "sudo ip netns exec osnd-gwp bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw \
        "${QPERF_BIN_LOCAL} -P ${SV_LAN_SERVER_IP%%/*} -p 18080 --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc_gw} -i ${REPORT_INTERVAL} -b ${tbs_gw} -q ${qbs_gw} -u ${ubs_gw} -w ${iw_gw} --max-ack-delay ${max_ack_delay} --first-ack-freq-packet-number ${first_ack_freq_packet_number} --ack-freq-cwnd-fraction ${ack_freq_cwnd_fraction} --listen-addr ${GW_LAN_PROXY_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_proxy_gw.txt' 2> >(awk '{print(\"E\", \"qperf-gw-proxy:\", \$0)}' > ${OSND_TMP}/logging)" \
        Enter

    # Satellite terminal proxy
    log D "Starting satellite terminal proxy"
    tmux -L ${TMUX_SOCKET} new-session -s qperf-proxy-st -d "sudo ip netns exec osnd-stp bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st \
        "${QPERF_BIN_LOCAL} -P ${GW_LAN_PROXY_IP%%/*} -p 18080 --tls-cert ${QPERF_CRT} --tls-key ${QPERF_KEY} --cc ${cc_st} -i ${REPORT_INTERVAL} -b ${tbs_st} -q ${qbs_st} -u ${ubs_st} -w ${iw_st} --max-ack-delay ${max_ack_delay} --first-ack-freq-packet-number ${first_ack_freq_packet_number} --ack-freq-cwnd-fraction ${ack_freq_cwnd_fraction} --listen-addr ${CL_LAN_ROUTER_IP%%/*} --listen-port 18080 --print-raw > '${output_dir}/${run_id}_proxy_st.txt' 2> >(awk '{print(\"E\", \"qperf-st-proxy:\", \$0)}' > ${OSND_TMP}/logging)" \
        Enter
}

# _osnd_quic_proxies_stop()
function _osnd_quic_proxies_stop() {
    log I "Stopping qperf proxies"

    # Gateway proxy
    log D "Stopping gateway proxy"
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-gw C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-gw killall $(basename $QPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t qperf-proxy-gw >/dev/null 2>&1

    # Satellite terminal proxy
    log D "Stopping satellite terminal proxy"
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t qperf-proxy-st C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-st killall $(basename $QPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t qperf-proxy-st >/dev/null 2>&1
}

# _osnd_moon_measure_quic(scenario_config_name, output_dir, pep=false, timing=false, route, run_cnt=5)
function _osnd_moon_measure_quic() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local timing=${4:-false}
    local route="$5"
    local run_cnt=${6:-5}

    local -n scenario_config_ref=$scenario_config_name
    local base_run_id="quic"
    local name_ext=""
    local measure_secs=$MEASURE_TIME
    local timeout=$(echo "${MEASURE_TIME} * 1.1" | bc -l)
    local server_ip="${SV_LAN_SERVER_IP%%/*}"

    if [[ "$pep" == true ]]; then
        base_run_id="${base_run_id}_pep"
        name_ext="${name_ext} (PEP)"
        server_ip="${CL_LAN_ROUTER_IP%%/*}"
    fi
    if [[ "$timing" == true ]]; then
        base_run_id="${base_run_id}_ttfb"
        name_ext="${name_ext} timing"
        measure_secs=-1
        timeout=4
    fi

    for i in $(seq $run_cnt); do
        log I "QUIC${name_ext} run $i/$run_cnt"
        local run_id="${base_run_id}_$i"

        # Environment
        osnd_moon_setup $scenario_config_name "$output_dir" "$run_id" "$pep" "$route"
        sleep $MEASURE_WAIT

        # Server
        _osnd_moon_quic_server_start "$output_dir" "$run_id" "${scenario_config_ref['cc_sv']:-reno}" "${scenario_config_ref['tbs_sv']:-1M}" "${scenario_config_ref['qbs_sv']:-1M}" "${scenario_config_ref['ubs_sv']:-1M}" "${scenario_config_ref['iw_sv']:-10}" "${scenario_config['max_ack_delay']:-25}" "${scenario_config['first_ack_freq_packet_number']:-1000}" "${scenario_config['ack_freq_cwnd_fraction']:-8}" "${scenario_config['qlog_file_server']}"
        sleep $MEASURE_WAIT

        # Proxy
        if [[ "$pep" == true ]]; then
            _osnd_quic_proxies_start "$output_dir" "$run_id" "${scenario_config_ref['cc_gw']:-reno}" "${scenario_config_ref['cc_st']:-reno}" "${scenario_config_ref['tbs_gw']:-1M}" "${scenario_config_ref['tbs_st']:-1M}" "${scenario_config_ref['qbs_gw']:-1M}" "${scenario_config_ref['qbs_st']:-1M}" "${scenario_config_ref['ubs_gw']:-1M}" "${scenario_config_ref['ubs_st']:-1M}" "${scenario_config_ref['iw_gw']:-10}" "${scenario_config_ref['iw_st']:-10}" "${scenario_config_ref['max_ack_delay']:-25}" "${scenario_config_ref['first_ack_freq_packet_number']:-1000}" "${scenario_config_ref['ack_freq_cwnd_fraction']:-8}"
            sleep $MEASURE_WAIT
        fi

        # Client
        _osnd_moon_quic_measure "$output_dir" "$run_id" "${scenario_config_ref['cc_cl']:-reno}" "${scenario_config_ref['tbs_cl']:-1M}" "${scenario_config_ref['qbs_cl']:-1M}" "${scenario_config_ref['ubs_cl']:-1M}" "${scenario_config_ref['iw_cl']:-10}" "${scenario_config['max_ack_delay']:-25}" "${scenario_config['first_ack_freq_packet_number']:-1000}" "${scenario_config['ack_freq_cwnd_fraction']:-8}" "${scenario_config['qlog_file_client']}" $measure_secs $timeout "$server_ip"
        sleep $MEASURE_GRACE

        # Cleanup
        if [[ "$pep" == true ]]; then
            _osnd_quic_proxies_stop
        fi
        _osnd_moon_quic_server_stop
        osnd_moon_teardown

        sleep $RUN_WAIT
    done
}

# osnd_moon_run_quic_goodput(scenario_config_name, output_dir, pep=false, route, run_cnt=4)
# Run QUIC goodput measurements on the emulation environment
function osnd_moon_measure_quic_goodput() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local route="$4"
    local run_cnt=${5:-4}

    _osnd_moon_measure_quic $scenario_config_name "$output_dir" $pep false "$route" $run_cnt
}

# osnd_moon_run_quic_ttfb(scenario_config_name, output_dir, pep=false, route, run_cnt=12)
# Run QUIC timing measurements on the emulation environment
function osnd_moon_measure_quic_timing() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local route="$4"
    local run_cnt=${5:-12}

    _osnd_moon_measure_quic $scenario_config_name "$output_dir" $pep true "$route" $run_cnt
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
        osnd_moon_measure_quic_goodput scenario_config "$@"
    else
        osnd_moon_measure_quic_goodput scenario_config "." 0 1
    fi
fi
