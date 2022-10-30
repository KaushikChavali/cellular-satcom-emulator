#!/bin/bash
# Environment configuration
# Don't use relative paths as some commands are executed in a rooted sub-shell

# File and directory paths

# qperf binary
QPERF_BIN="$HOME/build-qperf/qperf"
# Certificate and key used by qperf
QPERF_CRT="$HOME/server.crt"
QPERF_KEY="$HOME/server.key"
# pepsal binary
PEPSAL_BIN="$HOME/pepsal/src/pepsal"
# iperf3 binary
IPERF_BIN="/usr/bin/iperf"
# GStreamer binary
GST_BIN="$HOME/gst-app/bin/gst_rtp"
# GST video timecode path
GST_TIMECODE="$HOME/gst-timecode"
# GStreamer RTP-over-QUIC dir
ROQ_DIR="$HOME/rtp-over-quic"
# GStreamer RTP-over-QUIC binary
ROQ_BIN="$HOME/rtp-over-quic/roq"
# GStreamer file src
GST_FILESRC="${SCRIPT_DIR}/test_video.mp4"
# GStreamer roq file src
ROQ_FILESRC="$HOME/rtp-over-quic/train_30_30min.mp4"
# GStreamer plugin path
GST_PLUGIN_PATH="$HOME/gst-timecode/builddir/"
# GStreamer init bitrate
GST_INIT_BITRATE=10000000
# h2o binary
H2O_BIN="/usr/local/bin/h2o"
# python binary
PYTHON_BIN="/usr/bin/python3"
# chrome driver
CHROME_DRIVER_BIN="/usr/bin/chromedriver"
# Default OpenSAND entity configurations
OPENSAND_CONFIGS="${SCRIPT_DIR}/config"
# Nginx configuration
NGINX_CONFIG="${SCRIPT_DIR}/config/nginx.conf"
# Output directory for all emulations (one subdirectory per emulation will be created)
RESULTS_DIR="${SCRIPT_DIR}/out"
# MoonGen binary
MOONGEN_BIN="$HOME/MoonGen/build/MoonGen"
# MoonGen LTE script dir
MOONGEN_SCRIPT_DIR="$HOME/MoonGen/examples"
# MoonGen LTE script title
MOONGEN_SCRIPT="lte-emulator-handover-air.lua"
# OpenSAND directory
OSND_DIR="${SCRIPT_DIR}/quic-opensand-emulation"
# chromium python script
HTTP_SCRIPT="${OSND_DIR}/run_http_measurements.py"
# h2o configuration
H2O_CONFIG="${OSND_DIR}/h2o_config/h2o/h2o.conf"

# Opensand network config

# Emulation network used by the opensand entities
EMU_NET="10.3.3.0/24"
EMU_GW_IP="10.3.3.1/24"
EMU_ST_IP="10.3.3.2/24"
EMU_SAT_IP="10.3.3.254/24"

# Overlay network created by opensand to forward data through the emulated satellite
OVERLAY_NET_IPV6="fd81::/64"
OVERLAY_NET="10.81.81.0/24"
OVERLAY_GW_IP="10.81.81.1/24"
OVERLAY_ST_IP="10.81.81.2/24"

# Network at the gateway
GW_LAN_NET_IPV6="fd00:10:115:8::/64"
GW_LAN_NET="10.115.8.0/24"
GW_LAN_ROUTER_IP="10.115.8.1/24"
GW_LAN_PROXY_IP="10.115.8.10/24"

# Network at the satellite terminal
ST_LAN_NET_IPV6="fd00:192:168:3::/64"
ST_LAN_NET="192.168.3.0/24"
ST_LAN_ROUTER_IP="192.168.3.1/24"
ST_LAN_PROXY_IP="192.168.3.24/24"

# Network for the server
SV_LAN_NET="10.30.4.0/24"
SV_LAN_ROUTER_IP="10.30.4.1/24"
SV_LAN_SERVER_IP="10.30.4.18/24"

# Network for the server when multipath is enabled
SV_LAN_NET_MP="172.20.5.0/24"
SV_LAN_ROUTER_IP_MP="172.20.5.100/24"
SV_LAN_SERVER_IP_MP="172.20.5.116/24"

# Network for the client (via OpenSAND)
CL_LAN_NET="192.168.26.0/24"
CL_LAN_ROUTER_IP="192.168.26.1/24"
CL_LAN_CLIENT_IP="192.168.26.34/24"

# Network for the client (via MoonGen)
CL_LAN_NET_MG="172.20.5.0/24"
CL_LAN_ROUTER_IP_MG="172.20.5.1/24"
CL_LAN_CLIENT_IP_MG="172.20.5.16/24"

# Bridge mac addresses (specified in opensand configuration, see topology.conf)
BR_ST_MAC="de:ad:be:ef:00:02"
BR_EMU_MAC="de:ad:be:ef:00:ff"
BR_GW_MAC="de:ad:be:ef:00:01"

# Timings and advanced config

# How long to run the measurements (in seconds)
MEASURE_TIME=1800
# Seconds to wait after the environment has been started and before the measurements are executed
MEASURE_WAIT=3
# Seconds to wait after a measurement before stopping the server and environment
MEASURE_GRACE=3
# Seconds to wait after one measurement run
RUN_WAIT=1
# Seconds between reports of a measurement
REPORT_INTERVAL=0.1
# Seconds to wait after sending a stop signal to a running command
CMD_SHUTDOWN_WAIT=0.1
# Seconds to wait after opening a new tmux session
TMUX_INIT_WAIT=0.1
# Seconds to wait after modifying the testbed
CMD_CONFIG_PAUSE=0.5
# Name of the tmux socket to run all the sessions on
TMUX_SOCKET="opensand-moongen"
# tcpdump snapshot length (in bytes)
SNAP_LEN=96
