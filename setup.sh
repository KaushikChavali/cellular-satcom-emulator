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

# _add_mptcp_modules
function _add_mptcp_modules() {
	# Load MPTCP modules
	# Congestion controls
	sudo modprobe mptcp_olia
	sudo modprobe mptcp_coupled
	sudo modprobe mptcp_balia
	sudo modprobe mptcp_wvegas

	# Schedulers
	sudo modprobe mptcp_rr
	sudo modprobe mptcp_redundant
	sudo modprobe mptcp_blest

	# Path managers
	sudo modprobe mptcp_ndiffports
	sudo modprobe mptcp_binder
}

# _add_mpdccp_modules
function _add_mpdccp_modules() {
	# Load MPDCCP modules
	sudo modprobe mpdccp
	sudo modprobe mpdccp_reorder_fixed

	# Schedulers
	sudo modprobe mpdccp_sched_srtt
	sudo modprobe mpdccp_sched_otias
	sudo modprobe mpdccp_sched_rr
	sudo modprobe mpdccp_sched_redundant
	sudo modprobe mpdccp_sched_handover
	sudo modprobe mpdccp_sched_cpf
}

# _configure_mptcp_options(mptcp_cc, mptcp_pm, mptcp_sched)
function _configure_mptcp_options() {
	local mptcp_cc="$1"
	local mptcp_pm="$2"
	local mptcp_sched="$3"

	# Enable MPTCP on the machine
    sudo sysctl -wq net.mptcp.mptcp_enabled=1

	# Configure the path-manager;
	# default, fullmesh, ndiffports, binder, netlink
	sudo sysctl -wq net.mptcp.mptcp_path_manager="$mptcp_pm"

	# Configure the scheduler;
	# default, roundrobin, redundant, blest
	sudo sysctl -wq net.mptcp.mptcp_scheduler="$mptcp_sched"

	# Configure the congestion control algorithm;
	# reno, cubic, lia, olia, wVegas, balia
	sudo ip netns exec osnd-moon-cl sysctl -wq net.ipv4.tcp_congestion_control="$mptcp_cc"
	sudo ip netns exec osnd-moon-sv sysctl -wq net.ipv4.tcp_congestion_control="$mptcp_cc"
}

# _configure_mpdccp_options(mpdccp_cc, mpdccp_pm, mpdccp_sched, mpdccp_re)
function _configure_mpdccp_options() {
	local mpdccp_cc="$1"
	local mpdccp_pm="$2"
	local mpdccp_sched="$3"
	local mpdccp_re="$4"

	# Enable MPDCCP debugging (Kernel bug preventing safe environment teardown)
	sudo sysctl -wq net.mpdccp.mpdccp_debug=1

	# Configure the path-manager;
	# default
	sudo sysctl -wq net.mpdccp.mpdccp_path_manager="$mpdccp_pm"

	# Configure the scheduler;
	# default, srtt, rr, redundant, otias, cpf, handover
	sudo sysctl -wq net.mpdccp.mpdccp_scheduler="$mpdccp_sched"

	# Confingure reordering engine
	# default, fixed
	sudo sysctl -wq net.mpdccp.mpdccp_reordering="$mpdccp_re"

	# Configure the congestion control algorithm;
	# ccid2, ccid5
	if [[ "$mpdccp_cc" == "2" ]]; then
		# CCID2 configuration
		sudo sysctl -wq net.dccp.default.tx_ccid=2
		sudo sysctl -wq net.dccp.default.rx_ccid=2

		sudo sysctl -wq net.dccp.default.tx_qlen=20000

		# Default and maximum amount for the receive socket memory
		sudo sysctl -wq net.core.rmem_max=20000000
		sudo sysctl -wq net.core.rmem_default=20000000

		# Default and maximum amount for the send socket memory
		# Having a larger value avoids the cycle sleep/wakeup/send
		# on a waitqueue in the dccp_sendmsg() function, wich might
		# not be very efficient at high throughput
		sudo sysctl -wq net.core.wmem_max=20000000
		sudo sysctl -wq net.core.wmem_default=20000000
		sudo sysctl -wq net.core.netdev_max_backlog=1000000
	elif [[ "$mpdccp_cc" == "5" ]]; then
		# CCID5 configuration
		sudo sysctl -wq net.dccp.default.tx_ccid=5
		sudo sysctl -wq net.dccp.default.rx_ccid=5

		# Enable fq disc
		sudo echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
		sudo sysctl -p

		# Set fq flow limits
		sudo ip netns exec osnd-moon-cl tc qdisc replace dev ue3 root fq flow_limit 2000
		sudo ip netns exec osnd-moon-cl tc qdisc replace dev st3 root fq flow_limit 2000
		sudo ip netns exec osnd-moon-sv tc qdisc replace dev gw5 root fq flow_limit 2000

		sudo sysctl -wq net.dccp.default.tx_qlen=1000

		sudo sysctl -wq net.core.rmem_max=20000000
		sudo sysctl -wq net.core.rmem_default=2000000

		sudo sysctl -wq net.core.wmem_max=20000000
		sudo sysctl -wq net.core.wmem_default=2000000
		sudo sysctl -wq net.core.netdev_max_backlog=1000000
	fi

	# Enable MP-DCCP on the host interfaces
	# Client
	sudo tmux new-session -s config-mpdccp-cl -d "sudo ip netns exec osnd-moon-cl bash"
	tmp=`sudo ip netns exec osnd-moon-cl printf "0x%x\n" $((($(sudo ip netns exec osnd-moon-cl cat "/sys/class/net/st3/flags"))|0x200000))`
	sudo tmux send-keys -t config-mpdccp-cl "echo $tmp > "/sys/class/net/st3/flags"" Enter
	tmp=`sudo ip netns exec osnd-moon-cl printf "0x%x\n" $((($(sudo ip netns exec osnd-moon-cl cat "/sys/class/net/ue3/flags"))|0x200000))`
	sudo tmux send-keys -t config-mpdccp-cl "echo $tmp > "/sys/class/net/ue3/flags"" Enter
	tmp=
	# Set path priority for scheduler=cpf
	# LTE [mpdccp_prio=3 (default)] has higher priority than SATCOM [mpdccp_prio=100]
	if [[ "$mpdccp_sched" == "cpf" ]]; then
		sudo tmux send-keys -t config-mpdccp-cl "echo 100 > "/sys/module/mpdccplink/links/dev/st3/mpdccp_prio"" Enter
	fi
	sudo tmux kill-session -t config-mpdccp-cl

	# Server
	sudo tmux new-session -s config-mpdccp-sv -d "sudo ip netns exec osnd-moon-sv bash"
	tmp=`sudo ip netns exec osnd-moon-sv printf "0x%x\n" $((($(sudo ip netns exec osnd-moon-sv cat "/sys/class/net/gw5/flags"))|0x200000))`
	sudo tmux send-keys -t config-mpdccp-sv "echo $tmp > "/sys/class/net/gw5/flags"" Enter
	tmp=
	sudo tmux kill-session -t config-mpdccp-sv
}

# _config_mptcp_options(route, mptcp_cc, mptcp_pm, mptcp_sched)
function _set_mptcp_options() {
	local route="$1"
	local mptcp_cc="$2"
	local mptcp_pm="$3"
	local mptcp_sched="$4"

	if [[ "$route" == "MP" ]]; then
		# Add MPTCP modules to the Linux kernel
		_add_mptcp_modules

		# Configure MPTCP scenario options
		_configure_mptcp_options "$mptcp_cc" "$mptcp_pm" "$mptcp_sched"
	fi
}

# _config_mpdccp_options(route, mpdccp_cc, mpdccp_pm, mpdccp_sched)
function _set_mpdccp_options() {
	local route="$1"
	local mpdccp_cc="$2"
	local mpdccp_pm="$3"
	local mpdccp_sched="$4"
	local mpdccp_re="$5"

	if [[ "$route" == "MP" ]]; then
		# Add MPDCCP modules to the Linux kernel
		_add_mpdccp_modules
		# Configure MPDCCP scenario options
		_configure_mpdccp_options "$mpdccp_cc" "$mpdccp_pm" "$mpdccp_sched" "$mpdccp_re"
	fi
}

# _osnd_moon_log_mptcp_config()
function _osnd_moon_log_mptcp_config() {
	local mptcp_cc_cl=$(sudo ip netns exec osnd-moon-cl sysctl net.ipv4.tcp_congestion_control)
	local mptcp_cc_sv=$(sudo ip netns exec osnd-moon-sv sysctl net.ipv4.tcp_congestion_control)
	local mptcp_enabled_sv=$(sudo sysctl net.mptcp.mptcp_enabled)
	local mptcp_sched_sv=$(sudo sysctl net.mptcp.mptcp_scheduler)
	local mptcp_pm_sv=$(sudo sysctl net.mptcp.mptcp_path_manager)
	local mptcp_pm_cl_verbose=$(sudo ip netns exec osnd-moon-cl cat /proc/net/mptcp_fullmesh)
	local mptcp_pm_sv_verbose=$(sudo ip netns exec osnd-moon-sv cat /proc/net/mptcp_fullmesh)

	log I "MPTCP Configuration"
	log D "$mptcp_cc_cl"
	log D "$mptcp_cc_sv"
	log D "$mptcp_enabled_sv"
	log D "$mptcp_sched_sv"
	log D "$mptcp_pm_sv"
	log D "$mptcp_pm_cl_verbose"
	log D "$mptcp_pm_sv_verbose"
}

# _osnd_moon_log_mpdccp_config()
function _osnd_moon_log_mpdccp_config() {
	local mpdccp_cc_tx=$(sudo sysctl net.dccp.default.tx_ccid)
	local mpdccp_cc_rx=$(sudo sysctl net.dccp.default.rx_ccid)
	local mpdccp_sched=$(sudo sysctl net.mpdccp.mpdccp_scheduler)
	local mpdccp_pm=$(sudo sysctl net.mpdccp.mpdccp_path_manager)
	local mpdccp_re=$(sudo sysctl net.mpdccp.mpdccp_reordering)
	local mpdccp_prio_st3=$(sudo ip netns exec osnd-moon-cl cat /sys/module/mpdccplink/links/dev/st3/mpdccp_prio)
	local mpdccp_prio_ue3=$(sudo ip netns exec osnd-moon-cl cat /sys/module/mpdccplink/links/dev/ue3/mpdccp_prio)

	log I "MPDCCP Configuration"
	log D "$mpdccp_cc_tx"
	log D "$mpdccp_cc_rx"
	log D "$mpdccp_sched"
	log D "$mpdccp_pm"
	log D "$mpdccp_re"
	log D "$mpdccp_prio_st3"
	log D "$mpdccp_prio_ue3"
}

# _osnd_config_server_ip(route)
function _osnd_config_server_ip() {
	local route="$1"

	if [[ "$route" == "MP" ]]; then
		SV_LAN_NET="$SV_LAN_NET_MP"
		SV_LAN_ROUTER_IP="$SV_LAN_ROUTER_IP_MP"
		SV_LAN_SERVER_IP="$SV_LAN_SERVER_IP_MP"
	fi
}

# _osnd_orbit_ground_delay(orbit)
function _osnd_orbit_ground_delay() {
	local orbit="$1"

	case "$orbit" in
	"GEO") echo 40 ;;
	"MEO") echo 60 ;;
	"LEO") echo 10 ;;
	*) echo 0 ;;
	esac
}

# _osnd_moon_configure_cc(cc_cl, cc_st, cc_emu, cc_gw, cc_sv)
# Configure congestion control algorithms
function _osnd_moon_configure_cc() {
	local cc_cl="$1"
	local cc_st="$2"
	local cc_emu="$3"
	local cc_gw="$4"
	local cc_sv="$5"

	log D "Configuring congestion control algorithms"
	sudo ip netns exec osnd-moon-cl sysctl -wq net.ipv4.tcp_congestion_control="$cc_cl"
	sudo ip netns exec osnd-stp sysctl -wq net.ipv4.tcp_congestion_control="$cc_st"
	sudo ip netns exec osnd-st sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-emu sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-sat sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-gw sysctl -wq net.ipv4.tcp_congestion_control="$cc_emu"
	sudo ip netns exec osnd-gwp sysctl -wq net.ipv4.tcp_congestion_control="$cc_gw"
	sudo ip netns exec osnd-moon-sv sysctl -wq net.ipv4.tcp_congestion_control="$cc_sv"
}

# _osnd_moon_prime_env(seconds)
# Prime the environment with a few pings
function _osnd_moon_prime_env() {
	local seconds=$1

	log D "Priming environment"
	sudo timeout --foreground $(echo "$seconds + 1" | bc -l) ip netns exec osnd-moon-sv \
		ping -n -W 8 -c $(echo "$seconds * 100" | bc -l) -l 100 -i 0.01 ${CL_LAN_CLIENT_IP%%/*} >/dev/null
}

# _osnd_moon_capture(output_dir, run_id, pep, route, capture_nr)
# Start capturing packets
function _osnd_moon_capture() {
	local output_dir="$1"
	local run_id="$2"
	local pep="$3"
	local route="$4"
	local capture="$5"

	log D "Starting tcpdump"

	# Server
	tmux -L ${TMUX_SOCKET} new-session -s tcpdump-sv -d "sudo ip netns exec osnd-moon-sv bash"
	sleep $TMUX_INIT_WAIT
	tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-sv "tcpdump -i gw5 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_server_gw5.eth'" Enter

	if [[ "$pep" == true ]]; then
		# GW proxy
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-gw -d "sudo ip netns exec osnd-gw bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-gw "tcpdump -i gw1 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_proxy_gw1.eth'" Enter

		# ST proxy
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-st -d "sudo ip netns exec osnd-st bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-st "tcpdump -i st1 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_proxy_st1.eth'" Enter
	fi

	# Client
	if [[ "$route" == "LTE" ]]; then
		log D "Capturing dump at ue3 (LTE)"
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i ue3 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_client_ue3.eth'" Enter
	elif [[ "$route" == "SAT" ]]; then
		log D "Capturing dump at st3 (SATCOM)"
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl -d "sudo ip netns exec osnd-moon-cl bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl "tcpdump -i st3 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_client_st3.eth'" Enter
	else
		log D "Capturing dump at ue3 (LTE)"
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl-lte -d "sudo ip netns exec osnd-moon-cl bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl-lte "tcpdump -i ue3 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_client_ue3.eth'" Enter

		log D "Capturing dump at st3 (SATCOM)"
		tmux -L ${TMUX_SOCKET} new-session -s tcpdump-cl-sat -d "sudo ip netns exec osnd-moon-cl bash"
		sleep $TMUX_INIT_WAIT
		tmux -L ${TMUX_SOCKET} send-keys -t tcpdump-cl-sat "tcpdump -i st3 -s 65535 -c ${capture} -w '${output_dir}/${run_id}_dump_client_st3.eth'" Enter
	fi
}

# osnd_moon_setup(scenario_config_ref)
# Setup the entire emulation environment.
function osnd_moon_setup() {
	local -n scenario_config_ref="$1"
	local output_dir="${2:-.}"
	local run_id="${3:-manual}"
	local pep="${4:-false}"
	local route="${5:-MP}"

	# Extract associative array with defaults
	local cc_cl="${scenario_config_ref['cc_cl']:-reno}"
	local cc_st="${scenario_config_ref['cc_st']:-reno}"
	local cc_emu="${scenario_config_ref['cc_emu']:-reno}"
	local cc_gw="${scenario_config_ref['cc_gw']:-reno}"
	local cc_sv="${scenario_config_ref['cc_sv']:-reno}"
	local prime="${scenario_config_ref['prime']:-4}"
	local orbit="${scenario_config_ref['orbit']:-NONE}"
	local attenuation="${scenario_config_ref['attenuation']:-0}"
	local modulation_id="${scenario_config_ref['modulation_id']:-1}"
	local dump="${scenario_config_ref['dump']:-65535}"

	local delay_ground="$(_osnd_orbit_ground_delay "$orbit")"
	local delay_cl_sat="${scenario_config_ref['delay_cl_sat']:-0}"
	local delay_cl_lte="${scenario_config_ref['delay_cl_lte']:-0}"
	local delay_sv="${scenario_config_ref['delay_sv']:-0}"
	local delay_gw="${scenario_config_ref['delay_gw']:-9}"
	local delay_st="${scenario_config_ref['delay_st']:-10}"
	local packet_loss="${scenario_config_ref['loss']:-0.166}"

	local iw_sv="${scenario_config['iw_sv']}"
	local iw_gw="${scenario_config['iw_gw']}"
	local iw_st="${scenario_config['iw_st']}"
	local iw_cl="${scenario_config['iw_cl']}"

	local mp_cc="${scenario_config_ref['mp_cc']:-lia}"
	local mp_pm="${scenario_config_ref['mp_pm']:-fullmesh}"
	local mp_sched="${scenario_config_ref['mp_sched']:-default}"
	local mp_prot="${scenario_config_ref['mp_prot']:-MPTCP}"
	local mp_re="${scenario_config_ref['mp_re']:-default}"

	log I "Setting up emulation environment"

	_osnd_config_server_ip "$route"
	sleep 1
	osnd_setup_namespaces "$delay_ground" "$packet_loss" "$iw_sv" "$iw_gw" "$iw_st" "$iw_cl"
	sleep 1
	osnd_reconfig_namespaces
	sleep 1
	moon_setup_namespaces "$iw_sv" "$iw_cl"
	sleep 1
	osnd_moon_setup_namespaces
	sleep 1
	osnd_moon_config_routes "$route" "$iw_sv" "$iw_cl"
	sleep 1
	osnd_moon_setup_ground_delay "$delay_ground" "$delay_cl_sat" "$delay_cl_lte" "$delay_sv"
	sleep 1
	if [[ "$mp_prot" == "MPTCP" ]]; then
		_osnd_moon_configure_cc "$cc_cl" "$cc_st" "$cc_emu" "$cc_gw" "$cc_sv"
		sleep 1
		_set_mptcp_options "$route" "$mp_cc" "$mp_pm" "$mp_sched"
		sleep 1
	elif [[ "$mp_prot" == "MPDCCP" ]]; then
		_set_mpdccp_options "$route" "$mp_cc" "$mp_pm" "$mp_sched" "$mp_re"
	fi
	osnd_setup_opensand "$delay_gw" "$delay_st" "$attenuation" "$modulation_id"
	sleep 1
	moon_setup_moongen "$output_dir" "$run_id"
	sleep 10
	if [[ "$mp_prot" == "MPTCP" ]]; then
		_osnd_moon_log_mptcp_config
	else
		_osnd_moon_log_mpdccp_config
	fi
	if (($(echo "$prime > 0" | bc -l))); then
		_osnd_moon_prime_env $prime
	fi
	if [ "$dump" -gt 0 ]; then
		_osnd_moon_capture "$output_dir" "$run_id" "$pep" "$route" "$dump"
	fi

	# Add delay so that priming OpenSAND does not affect LTE DRX states
	# Wait for DRX state to retrun to RCC_IDLE
	sleep 10

	log D "Environment set up"
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
	export OSND_MOON_TMP="$(mktemp -d --tmpdir opensand-moongen.XXXXXX)"
	set -a
	source "${CONFIG_DIR}/testbed-config.sh"
	source "${CONFIG_DIR}/moon-config.sh"
	source "${OSND_DIR}/setup-opensand.sh"
	source "${OSND_DIR}/setup-namespaces.sh"
	source "${SCRIPT_DIR}/setup-namespaces.sh"
	source "${SCRIPT_DIR}/setup-lte-namespaces.sh"
	source "${SCRIPT_DIR}/setup-moongen.sh"
	set +a

	osnd_moon_setup "$@" scenario_config
fi
