#!/bin/bash

# _osnd_moon_capture_start(output_dir, run_id, route)
function _osnd_moon_capture_start() {
    local output_dir="$1"
    local run_id="$2"
    local route="$3"

    log I "Starting tcpdump"

    # Server
    tmux -L ${TMUX_SOCKET} new-session -s tcpdump-sv -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-sv "ethtool -K gw5 tx off sg off tso off" Enter
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-sv "tcpdump -i gw5 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_server_gw5.pcap" Enter

    # Client
    if [[ "$route" == "LTE" ]]; then
        log D "Capturing dump at ue3 (LTE)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "ethtool -K ue3 tx off sg off tso off" Enter
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i ue3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_ue3.pcap" Enter
    elif [[ "$route" == "SAT" ]]; then
        log D "Capturing dump at st3 (SATCOM)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "ethtool -K st3 tx off sg off tso off" Enter
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i st3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_st3.pcap" Enter
    else
        log D "Capturing dump at ue3 (LTE) and st3 (SATCOM)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "ethtool -K ue3 tx off sg off tso off" Enter
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "ethtool -K st3 tx off sg off tso off" Enter
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i any -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_ue3_st3.pcap" Enter
    fi
}

# _capture_stop(tmux_ns)
function _capture_stop() {
    local tmux_ns="$1"

    tmux -L ${TMUX_SOCKET} send-keys -t ${tmux_ns} C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t ${tmux_ns} C-d
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} kill-session -t ${tmux_ns} >/dev/null 2>&1
}

# _osnd_moon_capture_stop()
function _osnd_moon_capture_stop() {
    local output_dir="$1"
    local run_id="$2"
    local route="$3"

    log I "Stopping tcpdump"

    # Server
    _capture_stop "tcpdump-sv"

    # Client
    _capture_stop "tcpdump-cl"
}

# _osnd_moon_iperf_measure_dl(output_dir, run_id, bandwidth, measure_secs, timeout, route)
function _osnd_moon_iperf_measure_dl() {
    local output_dir="$1"
    local run_id="$2"
    local bandwidth="$3"
    local measure_secs="$4"
    local timeout="$5"

    log I "Running iperf client on DL"
    tmux -L ${TMUX_SOCKET} new-session -s iperf-cl-dl -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    if [[ "$route" == "LTE" ]] || [[ "$route" == "SAT" ]]; then
        tmux -L ${TMUX_SOCKET} send-keys -t iperf-cl-dl "${IPERF_BIN} -c ${SV_LAN_SERVER_IP%%/*} -p 5201 -b ${bandwidth} -t $measure_secs -i ${REPORT_INTERVAL} --dccp --multipath -R -4 --logfile \"${output_dir}/${run_id}_iperf_dl_client.log\" 2>&1" Enter
    else
        tmux -L ${TMUX_SOCKET} send-keys -t iperf-cl-dl "${IPERF_BIN} -c ${SV_LAN_SERVER_IP_MP%%/*} -p 5201 -b ${bandwidth} -t $measure_secs -i ${REPORT_INTERVAL} --dccp --multipath -R -4 --logfile \"${output_dir}/${run_id}_iperf_dl_client.log\" 2>&1" Enter
    fi
}

# _osnd_moon_iperf_measure_ul(output_dir, run_id, bandwidth, measure_secs, timeout, route)
function _osnd_moon_iperf_measure_ul() {
    local output_dir="$1"
    local run_id="$2"
    local bandwidth="$3"
    local measure_secs="$4"
    local timeout="$5"

    log I "Running iperf client on UL"
    tmux -L ${TMUX_SOCKET} new-session -s iperf-cl-ul -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    if [[ "$route" == "LTE" ]] || [[ "$route" == "SAT" ]]; then
        tmux -L ${TMUX_SOCKET} send-keys -t iperf-cl-ul "${IPERF_BIN} -c ${SV_LAN_SERVER_IP%%/*} -p 4242 -b ${bandwidth} -t $measure_secs -i ${REPORT_INTERVAL} --dccp --multipath -4 --logfile \"${output_dir}/${run_id}_iperf_ul_client.log\" 2>&1" Enter
    else
        tmux -L ${TMUX_SOCKET} send-keys -t iperf-cl-ul "${IPERF_BIN} -c ${SV_LAN_SERVER_IP_MP%%/*} -p 4242 -b ${bandwidth} -t $measure_secs -i ${REPORT_INTERVAL} --dccp --multipath -4 --logfile \"${output_dir}/${run_id}_iperf_ul_client.log\" 2>&1" Enter
    fi
}

# _moon_iperf_client_stop(host_name, tmux_ns)
function _osnd_moon_iperf_client_stop() {
    local host_name="$1"
    local tmux_ns="$2"

    sudo ip netns exec $host_name killall $(basename $IPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t $tmux_ns >/dev/null 2>&1
}

# _osnd_moon_iperf_server_dl_start(output_dir, run_id)
function _osnd_moon_iperf_server_dl_start() {
    local output_dir="$1"
    local run_id="$2"

    log I "Starting iperf server on DL"
    sudo ip netns exec osnd-moon-sv killall $(basename $IPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} new-session -s iperf-dl -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t iperf-dl "${IPERF_BIN} -s -p 5201 -i ${REPORT_INTERVAL} -4 --logfile \"${output_dir}/${run_id}_iperf_dl_server.log\" 2>&1" Enter
}

# _osnd_moon_iperf_server_ul_start(output_dir, run_id)
function _osnd_moon_iperf_server_ul_start() {
    local output_dir="$1"
    local run_id="$2"

    log I "Starting iperf server on UL"
    tmux -L ${TMUX_SOCKET} new-session -s iperf-ul -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t iperf-ul "${IPERF_BIN} -s -p 4242 -i ${REPORT_INTERVAL} -4 --logfile \"${output_dir}/${run_id}_iperf_ul_server.log\" 2>&1" Enter
}

# _moon_iperf_server_stop(tmux_ns, host_name)
function _osnd_moon_iperf_server_stop() {
    local tmux_ns="$1"
    local host_name="$2"

    log I "Stopping iperf server"
    tmux -L ${TMUX_SOCKET} send-keys -t $tmux_ns C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t $tmux_ns C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec $host_name killall $(basename $IPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t $tmux_ns >/dev/null 2>&1
}

# _osnd_moon_extract_pcap()
function _osnd_moon_extract_pcap() {
    local output_dir="$1"
    local run_id="$2"
    local file="$3"

    xz -T0 ${output_dir}/${run_id}_${file}.pcap
}

# _osnd_moon_process_capture()
function _osnd_moon_process_capture() {
    local output_dir="$1"
    local run_id="$2"
    local route="$3"

    log I "Post-processing PCAPs in situ"

    # Server
    _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_server_gw5"

    # Client
    if [[ "$route" == "LTE" ]]; then
        _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_client_ue3"
    elif [[ "$route" == "SAT" ]]; then
        _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_client_st3"
    else
        _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_client_ue3_st3"
        xz -T0 ${output_dir}/${run_id}_dump_mptcp_queue_occ.log
    fi
}

# osnd_moon_measure_iperf_dccp_duplex_metrics(scenario_config_name, output_dir, pep=false, route, run_cnt=12)
# Run DCCP duplex traffic on the emulation environment with (MP)DCCP stream on the downlink (DL) emulating a
# constant bitrate (CBR) control traffic, and (MP)DCCP stream on the uplink (UL) mimicing a
# constant bitrate (CBR) telemetry and video traffic.
function osnd_moon_measure_iperf_dccp_duplex_metrics() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local route="$4"
    local run_cnt=${5:-4}

    local -n scenario_config_ref=$scenario_config_name
    local base_run_id="dccp_iperf_duplex"
    local name_ext=""
    local bw_ul="${scenario_config_ref['bw_ul']}"
    local bw_dl="${scenario_config_ref['bw_dl']}"

    if [[ "$pep" == true ]]; then
        log E "PEP not configured for DCCP. Defaulting to false."
    fi

    for i in $(seq $run_cnt); do
        log I "DCCP Duplex${name_ext} run $i/$run_cnt"
        local run_id="${base_run_id}_$i"

        # Environment
        osnd_moon_setup $scenario_config_name "$output_dir" "$run_id" "$pep" "$route"
        sleep $MEASURE_WAIT

        # Start iPerf servers
        _osnd_moon_iperf_server_dl_start "$output_dir" "$run_id"
        sleep $CMD_SHUTDOWN_WAIT
        _osnd_moon_iperf_server_ul_start "$output_dir" "$run_id"
        sleep $MEASURE_WAIT

        # Dump packets
        _osnd_moon_capture_start "$output_dir" "$run_id" "$route"

        # Start iPerf clients
        _osnd_moon_iperf_measure_dl "$output_dir" "$run_id" "$bw_dl" $MEASURE_TIME $(echo "${MEASURE_TIME} * 1.2" | bc -l)
        _osnd_moon_iperf_measure_ul "$output_dir" "$run_id" "$bw_ul" $MEASURE_TIME $(echo "${MEASURE_TIME} * 1.2" | bc -l)

        sleep $MEASURE_TIME
        sleep $MEASURE_GRACE

        _osnd_moon_iperf_client_stop "osnd-moon-cl" "iperf-cl-ul"
        _osnd_moon_iperf_client_stop "osnd-moon-cl" "iperf-cl-dl"

        _osnd_moon_iperf_server_stop "iperf-dl" "osnd-moon-sv"
        _osnd_moon_iperf_server_stop "iperf-ul" "osnd-moon-sv"
        
        _osnd_moon_capture_stop "$output_dir" "$run_id" "$route"
        osnd_moon_teardown

        # Do post-processing of PCAPs
        _osnd_moon_process_capture "$output_dir" "$run_id" "$route"

        sleep $RUN_WAIT
    done
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
        osnd_moon_measure_iperf_dccp_duplex_metrics scenario_config "$@"
    else
        osnd_moon_measure_iperf_dccp_duplex_metrics scenario_config "." 0 1
    fi
fi
