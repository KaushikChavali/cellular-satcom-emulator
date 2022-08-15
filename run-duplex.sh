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
    tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-sv "tcpdump -i gw5 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_server_gw5.pcap" Enter

    # Client
    if [[ "$route" == "LTE" ]]; then
        log D "Capturing dump at ue3 (LTE)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i ue3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_ue3.pcap" Enter
    elif [[ "$route" == "SAT" ]]; then
        log D "Capturing dump at st3 (SATCOM)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i st3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_st3.pcap" Enter
    else
        log D "Capturing dump at ue3 (LTE)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl-lte -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl-lte "tcpdump -i ue3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_ue3.pcap" Enter

        log D "Capturing dump at st3 (SATCOM)"
        tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl-sat -d "sudo ip netns exec osnd-moon-cl bash"
        sleep $TMUX_INIT_WAIT
        tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl-sat "tcpdump -i st3 -s ${SNAP_LEN} -w ${output_dir}/${run_id}_dump_client_st3.pcap" Enter
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
    if [[ "$route" == "LTE" ]] || [[ "$route" == "SAT" ]]; then
        _capture_stop "tcpdump-cl"
    else
        _capture_stop "tcpdump-cl-lte"
        _capture_stop "tcpdump-cl-sat"
    fi
}


# _osnd_moon_iperf_measure(output_dir, run_id, bandwidth, measure_secs, timeout)
function _osnd_moon_iperf_measure() {
    local output_dir="$1"
    local run_id="$2"
    local bandwidth="$3"
    local measure_secs="$4"
    local timeout="$5"

    log I "Running iperf client"
    tmux -L ${TMUX_SOCKET} new-session -s iperf-cl -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t iperf-cl "${IPERF_BIN} -c ${SV_LAN_SERVER_IP%%/*} -p 5201 -b ${bandwidth} -t $measure_secs -i ${REPORT_INTERVAL} -R -J --logfile '${output_dir}/${run_id}_client.json'" Enter
}


# _moon_iperf_client_stop(host_name, tmux_ns)
function _osnd_moon_iperf_client_stop() {
        local host_name="$1"
        local tmux_ns="$2"

        sudo ip netns exec $host_name killall $(basename $IPERF_BIN) -q
        tmux -L ${TMUX_SOCKET} kill-session -t $tmux_ns >/dev/null 2>&1
}


# _osnd_moon_gstreamer_client_start_roq_app(output_dir, run_id)
function _osnd_moon_gstreamer_client_start_roq_app() {
    local output_dir="$1"
    local run_id="$2"

    log I "Starting GStreamer client"
    sudo ip netns exec osnd-moon-sv killall $(basename $ROQ_BIN) -q
    tmux -L ${TMUX_SOCKET} new-session -s gst-cl -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl "cd ${GST_TIMECODE}" Enter
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl "export GST_PLUGIN_PATH='$(pwd)/builddir/'" Enter
    sleep $TMUX_INIT_WAIT
    ip netns exec osnd-moon-sv ${ROQ_BIN} receive -a :4242 --sink fpsdisplaysink --fps-dump ${output_dir}/${run_id}_receiver.fps.csv --rtp-dump ${output_dir}/${run_id}_receiver.rtp.csv --save ${output_dir}/${run_id}_receiver.avi --transport tcp &
}


# _osnd_moon_gstreamer_client_stop_roq_app()
function _osnd_moon_gstreamer_client_stop_roq_app() {
    log I "Stopping GStreamer client"
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-moon-sv killall $(basename $ROQ_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t gst-cl >/dev/null 2>&1
}


# _osnd_moon_gstreamer_server_start_roq_app(output_dir, run_id)
function _osnd_moon_gstreamer_server_start_roq_app() {
    local output_dir="$1"
    local run_id="$2"

    log I "Running GStreamer server"
    tmux -L ${TMUX_SOCKET} new-session -s gst-sv -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv "cd ${GST_TIMECODE}" Enter
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv "export GST_PLUGIN_PATH='$(pwd)/builddir/'" Enter
    sleep $TMUX_INIT_WAIT
    timeout ${MEASURE_TIME} ip netns exec osnd-moon-cl ${ROQ_BIN} send -a ${SV_LAN_SERVER_IP_MP%%/*}:4242 --source ${ROQ_FILESRC} --codec h264 --rtp-dump ${output_dir}/${run_id}_sender.rtp.csv --cc-dump ${output_dir}/${run_id}_sender.cc.csv --save ${output_dir}/${run_id}_sender.avi --transport tcp --init-rate 25000000
    log I "Measurement complete"
}


# _osnd_moon_gstreamer_server_stop_roq_app()
function _osnd_moon_gstreamer_server_stop_roq_app() {
    log I "Stopping GStreamer server"
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-moon-cl killall $(basename $ROQ_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t gst-sv >/dev/null 2>&1
}


# _osnd_moon_iperf_server_start(output_dir, run_id)
function _osnd_moon_iperf_server_start() {
    local output_dir="$1"
    local run_id="$2"

    log I "Starting iperf server"
    sudo ip netns exec osnd-moon-sv killall $(basename $IPERF_BIN) -q
    tmux -L ${TMUX_SOCKET} new-session -s iperf -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t iperf "${IPERF_BIN} -s -p 5201 -i ${REPORT_INTERVAL} -J --logfile '${output_dir}/${run_id}_server.json' 2> >(awk '{print(\"E\", \"iperf-server:\", \$0)}' > ${OSND_TMP}/logging)" Enter
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

    captcp throughput -s 1 -u bit -i -o ${output_dir} ${output_dir}/${run_id}_${file}.pcap >/dev/null 2>&1
    mv ${output_dir}/throughput.data ${output_dir}/${run_id}_${file}.data
    xz ${output_dir}/${run_id}_${file}.pcap
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
        _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_client_ue3"
        _osnd_moon_extract_pcap "$output_dir" "$run_id" "dump_client_st3"
    fi
}


# osnd_moon_measure_tcp_duplex_metrics(scenario_config_name, output_dir, pep=false, route, run_cnt=12)
# Run TCP duplex traffic on the emulation environment with TCP stream on the downlink (DL) emulating a
# constant bitrate (CBR) control traffic, and a RTP over (MP)TCP stream on the uplink (UL) mimicing a
# variable bitrate (VBR) telemetry and video traffic.

function osnd_moon_measure_tcp_duplex_metrics() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local route="$4"
    local run_cnt=${5:-4}

    local -n scenario_config_ref=$scenario_config_name
    local base_run_id="tcp_duplex"
    local name_ext=""
    local bw_ul="${scenario_config_ref['bw_ul']}"
    local bw_dl="${scenario_config_ref['bw_dl']}"

    if [[ "$pep" == true ]]; then
        base_run_id="${base_run_id}_pep"
        name_ext="${name_ext} (PEP)"
    fi

    for i in $(seq $run_cnt); do
        log I "TCP Duplex${name_ext} run $i/$run_cnt"
        local run_id="${base_run_id}_$i"

        # Environment
        osnd_moon_setup $scenario_config_name "$output_dir" "$run_id" "$pep" "$route"
        sleep $MEASURE_WAIT

        # Start iPerf server
        _osnd_moon_iperf_server_start "$output_dir" "$run_id"
        sleep $CMD_SHUTDOWN_WAIT

        # Start GStreamer client
        _osnd_moon_gstreamer_client_start_roq_app "$output_dir" "$run_id"
        sleep $MEASURE_WAIT

        # Proxy
        if [[ "$pep" == true ]]; then
            _osnd_pepsal_proxies_start "$output_dir" "$run_id"
            sleep $MEASURE_WAIT
        fi

        # Dump packets
        _osnd_moon_capture_start "$output_dir" "$run_id" "$route"

         # Start iPerf client        
        _osnd_moon_iperf_measure "$output_dir" "$run_id" "$bw_dl" $MEASURE_TIME $(echo "${MEASURE_TIME} * 1.2" | bc -l)

        # Start GStreamer server
        _osnd_moon_gstreamer_server_start_roq_app "$output_dir" "$run_id"
        sleep $MEASURE_GRACE

        _osnd_moon_iperf_client_stop "osnd-moon-cl" "client-dl"

        sleep $MEASURE_GRACE
        # Cleanup
        if [[ "$pep" == true ]]; then
            _osnd_pepsal_proxies_stop
        fi

        _osnd_moon_iperf_server_stop "iperf" "osnd-moon-sv"
        _osnd_moon_gstreamer_client_stop_roq_app
        _osnd_moon_gstreamer_server_stop_roq_app

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
        osnd_moon_measure_tcp_duplex_metrics scenario_config "$@"
    else
        osnd_moon_measure_tcp_duplex_metrics scenario_config "." 0 1
    fi
fi
