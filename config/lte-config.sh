#!/bin/bash
# Environment configuration
# Don't use relative paths as some commands are executed in a rooted sub-shell

# File and directory paths

# MoonGen binary
MOONGEN_BIN="$HOME/MoonGen/build/MoonGen"
# MoonGen LTE script dir
MOONGEN_SCRIPT_DIR="$HOME/MoonGen/examples"

# LTE network config

# Network for the server
SV_LAN_NET="10.30.4.0/24"
SV_LAN_ROUTER_IP="10.30.4.1/24"
SV_LAN_SERVER_IP="10.30.4.18/24"

# Network for the client (via MoonGen)
CL_LAN_NET_MG="172.20.5.0/24"
CL_LAN_ROUTER_IP_MG="172.20.5.1/24"
CL_LAN_CLIENT_IP_MG="172.20.5.16/24"

# Network for the client (via OpenSAND)
CL_LAN_NET="192.168.26.0/24"
CL_LAN_ROUTER_IP="192.168.26.1/24"
CL_LAN_CLIENT_IP="192.168.26.34/24"

# Timings and advanced config

# Seconds to wait after sending a stop signal to a running command
CMD_SHUTDOWN_WAIT=0.1
# Seconds to wait after opening a new tmux session
TMUX_INIT_WAIT=0.1
# Seconds to wait after modifying the testbed
CMD_CONFIG_PAUSE=0.5
# Name of the tmux socket to run all the sessions on
TMUX_SOCKET="moongen"
