#!/bin/bash

# _add_mptcp_modules
function _add_mptcp_modules() {
	# Load MPTCP modules
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

# _configure_mptcp_options(mptcp_cc, mptcp_pm, mptcp_sched)
function _configure_mptcp_options() {
	local mptcp_cc="$1"
	local mptcp_pm="$2"
	local mptcp_sched="$3"

	# Configure the path-manager;
	# default, fullmesh, ndiffports, binder, netlink
	sudo sysctl -wq net.mptcp.mptcp_path_manager="$mptcp_pm"

	# Configure the scheduler;
	# default, roundrobin, redundant, blest
	sudo sysctl -wq net.mptcp.mptcp_scheduler="$mptcp_sched"

	# Configure the congestion control algorithm;
	# lia, olia, wVegas, balia
	sudo sysctl -wq net.ipv4.tcp_congestion_control="$mptcp_cc"
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
	"LEO") echo 80 ;;
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
	sudo timeout --foreground $(echo "$seconds + 1" | bc -l) ip netns exec osnd-moon-cl \
		ping -n -W 8 -c $(echo "$seconds * 100" | bc -l) -l 100 -i 0.01 ${SV_LAN_SERVER_IP%%/*} >/dev/null
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
	local route="${5:-LTE}"

	# Extract associative array with defaults
	local cc_cl="${scenario_config_ref['cc_cl']:-reno}"
	local cc_st="${scenario_config_ref['cc_st']:-reno}"
	local cc_emu="${scenario_config_ref['cc_emu']:-reno}"
	local cc_gw="${scenario_config_ref['cc_gw']:-reno}"
	local cc_sv="${scenario_config_ref['cc_sv']:-reno}"
	local prime="${scenario_config_ref['prime']:-4}"
	local orbit="${scenario_config_ref['orbit']:-GEO}"
	local attenuation="${scenario_config_ref['attenuation']:-0}"
	local modulation_id="${scenario_config_ref['modulation_id']:-1}"
	local dump="${scenario_config_ref['dump']:-65535}"

	local delay_ground="$(_osnd_orbit_ground_delay "$orbit")"
	local delay_cl_sat="${scenario_config_ref['delay_cl_sat']:-0}"
	local delay_cl_lte="${scenario_config_ref['delay_cl_lte']:-0}"
	local delay_sv="${scenario_config_ref['delay_sv']:-0}"
	local delay_gw="${scenario_config_ref['delay_gw']:-125}"
	local delay_st="${scenario_config_ref['delay_st']:-125}"
	local packet_loss="${scenario_config_ref['loss']:-0}"

	local iw_sv="${scenario_config['iw_sv']}"
	local iw_gw="${scenario_config['iw_gw']}"
	local iw_st="${scenario_config['iw_st']}"
	local iw_cl="${scenario_config['iw_cl']}"

	local mp_cc="${scenario_config_ref['mp_cc']:-lia}"
	local mp_pm="${scenario_config_ref['mp_pm']:-fullmesh}"
	local mp_sched="${scenario_config_ref['mp_sched']:-default}"

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
	_osnd_moon_configure_cc "$cc_cl" "$cc_st" "$cc_emu" "$cc_gw" "$cc_sv"
	sleep 1
	_set_mptcp_options "$route" "$mp_cc" "$mp_pm" "$mp_sched"
	sleep 1
	osnd_setup_opensand "$delay_gw" "$delay_st" "$attenuation" "$modulation_id"
	sleep 1
	moon_setup_moongen "$output_dir" "$run_id"
	sleep 10

	if [ "$dump" -gt 0 ]; then
		_osnd_moon_capture "$output_dir" "$run_id" "$pep" "$route" "$dump"
	fi

	if (($(echo "$prime > 0" | bc -l))); then
		_osnd_moon_prime_env $prime
	fi

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
