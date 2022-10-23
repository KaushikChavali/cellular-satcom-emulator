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

# _osnd_pepsal_proxies_start(output_dir, run_id)
function _osnd_pepsal_proxies_start() {
    local output_dir="$1"
    local run_id="$2"
    local error_redirect=""

    log I "Starting pepsal proxies"

    # Gateway proxy
    log D "Starting gateway proxy"
    error_redirect="2> >(awk '{print(\"E\", \"pepsal-gw-proxy:\", \$0)}' > ${OSND_TMP}/logging)"
    tmux -L ${TMUX_SOCKET} new-session -s pepsal-gw -d "sudo ip netns exec osnd-gwp bash"
    sleep $TMUX_INIT_WAIT
    # Route marked traffic to pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "ip rule add fwmark 1 lookup 100 $error_redirect" Enter
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "ip route add local 0.0.0.0/0 dev lo table 100 $error_redirect" Enter
    # Mark selected traffic for processing by pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "iptables -t mangle -A PREROUTING -i gw1 -p tcp -j TPROXY --on-port 5201 --tproxy-mark 1 $error_redirect" Enter
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "iptables -t mangle -A PREROUTING -i gw2 -p tcp -j TPROXY --on-port 5201 --tproxy-mark 1 $error_redirect" Enter
    # Start pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw "${PEPSAL_BIN} -p 5201 -l '${output_dir}/${run_id}_proxy_gw.txt' $error_redirect" Enter

    # Satellite terminal proxy
    log D "Starting satellite terminal proxy"
    error_redirect="2> >(awk '{print(\"E\", \"pepsal-st-proxy:\", \$0)}' > ${OSND_TMP}/logging)"
    tmux -L ${TMUX_SOCKET} new-session -s pepsal-st -d "sudo ip netns exec osnd-stp bash"
    sleep $TMUX_INIT_WAIT
    # Route marked traffic to pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "ip rule add fwmark 1 lookup 100 $error_redirect" Enter
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "ip route add local 0.0.0.0/0 dev lo table 100 $error_redirect" Enter
    # Mark selected traffic for processing by pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "iptables -t mangle -A PREROUTING -i st1 -p tcp -j TPROXY --on-port 5201 --tproxy-mark 1 $error_redirect" Enter
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st "iptables -t mangle -A PREROUTING -i st2 -p tcp -j TPROXY --on-port 5201 --tproxy-mark 1 $error_redirect" Enter
    # Start pepsal
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st \
        "${PEPSAL_BIN} -p 5201 -l '${output_dir}/${run_id}_proxy_st.txt' $error_redirect" \
        Enter
}

# _osnd_pepsal_proxies_stop()
function _osnd_pepsal_proxies_stop() {
    log I "Stopping pepsal proxies"

    # Gateway proxy
    log D "Stopping gateway proxy"
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-gw C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-gw killall $(basename $PEPSAL_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t pepsal-gw >/dev/null 2>&1

    # Satellite terminal proxy
    log D "Stopping satellite terminal proxy"
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st C-c
    sleep $CMD_SHUTDOWN_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t pepsal-st C-d
    sleep $CMD_SHUTDOWN_WAIT
    sudo ip netns exec osnd-st killall $(basename $PEPSAL_BIN) -q
    tmux -L ${TMUX_SOCKET} kill-session -t pepsal-st >/dev/null 2>&1
}

# _osnd_moon_gstreamer_client_start_roq_app(output_dir, run_id)
function _osnd_moon_gstreamer_client_start_roq_app() {
    local output_dir="$1"
    local run_id="$2"
    local save_video="$3"

    log I "Starting GStreamer client"
    sudo ip netns exec osnd-moon-sv killall $(basename $ROQ_BIN) -q
    tmux -L ${TMUX_SOCKET} new-session -s gst-cl -d "sudo ip netns exec osnd-moon-sv bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl "cd ${GST_TIMECODE}" Enter
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-cl "export GST_PLUGIN_PATH='$(pwd)/builddir/'" Enter
    sleep $TMUX_INIT_WAIT
    if [[ "$save_video" == true ]]; then
        (cd ${ROQ_DIR} && ip netns exec osnd-moon-sv ${ROQ_BIN} receive -a :4242 --sink fpsdisplaysink --fps-dump ${output_dir}/${run_id}_receiver.fps.csv --rtp-dump ${output_dir}/${run_id}_receiver.rtp.csv --save ${output_dir}/${run_id}_receiver.avi --transport tcp &)
    else
        (cd ${ROQ_DIR} && ip netns exec osnd-moon-sv ${ROQ_BIN} receive -a :4242 --sink fpsdisplaysink --fps-dump ${output_dir}/${run_id}_receiver.fps.csv --rtp-dump ${output_dir}/${run_id}_receiver.rtp.csv --save /dev/null --transport tcp &)
    fi
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
    local route="$3"
    local route="$4"

    log I "Running GStreamer server"
    tmux -L ${TMUX_SOCKET} new-session -s gst-sv -d "sudo ip netns exec osnd-moon-cl bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv "cd ${GST_TIMECODE}" Enter
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t gst-sv "export GST_PLUGIN_PATH='$(pwd)/builddir/'" Enter
    sleep $TMUX_INIT_WAIT
    if [[ "$save_video" == true ]]; then
        if [[ "$route" == "LTE" ]] || [[ "$route" == "SAT" ]]; then
            (cd ${ROQ_DIR} && timeout ${MEASURE_TIME} ip netns exec osnd-moon-cl ${ROQ_BIN} send -a ${SV_LAN_SERVER_IP%%/*}:4242 --source ${ROQ_FILESRC} --codec h264 --rtp-dump ${output_dir}/${run_id}_sender.rtp.csv --cc-dump ${output_dir}/${run_id}_sender.cc.csv --save ${output_dir}/${run_id}_sender.avi --transport tcp --init-rate 25000000)
        else
            (cd ${ROQ_DIR} && timeout ${MEASURE_TIME} ip netns exec osnd-moon-cl ${ROQ_BIN} send -a ${SV_LAN_SERVER_IP_MP%%/*}:4242 --source ${ROQ_FILESRC} --codec h264 --rtp-dump ${output_dir}/${run_id}_sender.rtp.csv --cc-dump ${output_dir}/${run_id}_sender.cc.csv --save ${output_dir}/${run_id}_sender.avi --transport tcp --init-rate 25000000)
        fi
    else
        if [[ "$route" == "LTE" ]] || [[ "$route" == "SAT" ]]; then
            (cd ${ROQ_DIR} && timeout ${MEASURE_TIME} ip netns exec osnd-moon-cl ${ROQ_BIN} send -a ${SV_LAN_SERVER_IP%%/*}:4242 --source ${ROQ_FILESRC} --codec h264 --rtp-dump ${output_dir}/${run_id}_sender.rtp.csv --cc-dump ${output_dir}/${run_id}_sender.cc.csv --save /dev/null --transport tcp --init-rate 25000000)
        else
            (cd ${ROQ_DIR} && timeout ${MEASURE_TIME} ip netns exec osnd-moon-cl ${ROQ_BIN} send -a ${SV_LAN_SERVER_IP_MP%%/*}:4242 --source ${ROQ_FILESRC} --codec h264 --rtp-dump ${output_dir}/${run_id}_sender.rtp.csv --cc-dump ${output_dir}/${run_id}_sender.cc.csv --save /dev/null --transport tcp --init-rate 25000000)
        fi
    fi
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
    fi
}

# osnd_moon_measure_rtp_metrics_with_roq(scenario_config_name, output_dir, pep=false, route, run_cnt=4)
# Run RTP measurements utilizing GStreamer framework on the emulation environment
function osnd_moon_measure_rtp_metrics_with_roq() {
    local scenario_config_name=$1
    local output_dir="$2"
    local pep=${3:-false}
    local route="$4"
    local run_cnt=${5:-4}

    local -n scenario_config_ref=$scenario_config_name
    local base_run_id="rtp"
    local name_ext=""
    local save_video="${scenario_config_ref['save_video']}"

    if [[ "$pep" == true ]]; then
        base_run_id="${base_run_id}_pep"
        name_ext="${name_ext} (PEP)"
    fi

    for i in $(seq $run_cnt); do
        log I "RTP${name_ext} run $i/$run_cnt"
        local run_id="${base_run_id}_$i"

        # Environment
        osnd_moon_setup $scenario_config_name "$output_dir" "$run_id" "$pep" "$route"
        sleep $MEASURE_WAIT

        # GStreamer Client
        _osnd_moon_gstreamer_client_start_roq_app "$output_dir" "$run_id" "$save_video"
        sleep $MEASURE_WAIT

        # Proxy
        if [[ "$pep" == true ]]; then
            _osnd_pepsal_proxies_start "$output_dir" "$run_id"
            sleep $MEASURE_WAIT
        fi

        # Dump packets
        _osnd_moon_capture_start "$output_dir" "$run_id" "$route"

        # GStreamer Server
        _osnd_moon_gstreamer_server_start_roq_app "$output_dir" "$run_id" "$route" "$save_video"
        sleep $MEASURE_GRACE

        # Cleanup
        if [[ "$pep" == true ]]; then
            _osnd_pepsal_proxies_stop
        fi
        # _osnd_moon_gstreamer_server_stop
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
        osnd_moon_measure_rtp_metrics_with_roq scenario_config "$@"
    else
        osnd_moon_measure_rtp_metrics_with_roq scenario_config "." 0 1
    fi
fi
