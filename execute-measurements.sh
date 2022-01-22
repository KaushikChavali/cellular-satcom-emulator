#!/bin/bash
set -o nounset
set -o errtrace
set -o functrace

export SCRIPT_VERSION="2.1.0"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export CONFIG_DIR="${SCRIPT_DIR}/config"
export OSND_DIR="${SCRIPT_DIR}/quic-opensand-emulation"

set -o allexport
source "${CONFIG_DIR}/testbed-config.sh"
source "${CONFIG_DIR}/moon-config.sh"
set +o allexport

source "${OSND_DIR}/setup.sh"
source "${OSND_DIR}/setup-namespaces.sh"
source "${OSND_DIR}/setup-opensand.sh"
source "${OSND_DIR}/teardown.sh"
source "${OSND_DIR}/teardown-namespaces.sh"
source "${OSND_DIR}/teardown-opensand.sh"
source "${OSND_DIR}/run-ping.sh"
source "${OSND_DIR}/run-quic.sh"
source "${OSND_DIR}/run-tcp.sh"
source "${OSND_DIR}/run-http.sh"
source "${OSND_DIR}/stats.sh"

source "${SCRIPT_DIR}/setup.sh"
source "${SCRIPT_DIR}/setup-namespaces.sh"
source "${SCRIPT_DIR}/setup-moongen.sh"
source "${SCRIPT_DIR}/setup-lte.sh"
source "${SCRIPT_DIR}/setup-lte-namespaces.sh"
source "${SCRIPT_DIR}/setup-dependencies.sh"
source "${SCRIPT_DIR}/teardown.sh"
source "${SCRIPT_DIR}/teardown-namespaces.sh"
source "${SCRIPT_DIR}/teardown-moongen.sh"
source "${SCRIPT_DIR}/teardown-lte.sh"
source "${SCRIPT_DIR}/teardown-lte-namespaces.sh"
source "${SCRIPT_DIR}/teardown-dependencies.sh"
source "${SCRIPT_DIR}/run-ping.sh"
source "${SCRIPT_DIR}/run-quic.sh"
source "${SCRIPT_DIR}/run-tcp.sh"
source "${SCRIPT_DIR}/run-http.sh"
declare -A pids

# log(level, message...)
# Log a message of the specified level to the output and the log file.
function log() {
	local level="$1"
	shift
	local msg="$@"

	if [[ "$level" == "-" ]] || [[ "$msg" == "-" ]]; then
		if [[ "$level" == "-" ]]; then
			# Level will be read from stdin
			level=""
		fi

		# Log each line in stdin as separate log message
		while read -r err_line; do
			log $level $err_line
		done < <(cat -)
		return
	fi

	local log_time="$(date --rfc-3339=seconds)"
	local level_name="INFO"
	local level_color="\e[0m"
	local visible=true
	case $level in
	D | d)
		level_name="DEBUG"
		level_color="\e[2m"
		;;
	S | s)
		level_name="STAT"
		level_color="\e[34m"
		visible=$show_stats
		;;
	I | i)
		level_name="INFO"
		level_color="\e[0m"
		;;
	W | w)
		level_name="WARN"
		level_color="\e[33m"
		;;
	E | e)
		level_name="ERROR"
		level_color="\e[31m"
		;;
	*)
		# No level given, assume info
		msg="$level $msg"
		level="I"
		level_name="INFO"
		level_color="\e[0m"
		;;
	esac

	# Build and print log message
	local log_entry="$log_time [$level_name]: $msg"
	if [[ "$visible" == true ]]; then
		echo -e "$level_color$log_entry\e[0m"
	fi

	if [ -d "$EMULATION_DIR" ]; then
		echo "$log_entry" >>"$EMULATION_DIR/opensand-moongen.log"
	fi
}

# _osnd_moon_cleanup()
function _osnd_moon_cleanup() {
	# Ensure all tmux sessions are closed
	tmux -L ${TMUX_SOCKET} kill-server &>/dev/null

	# Remove temporary directory
	rm -rf "$OSND_MOON_TMP" &>/dev/null
}

# _osnd_moon_abort_measurements()
# Trap function executed on the EXIT trap during active measurements.
function _osnd_moon_abort_measurements() {
	log E "Aborting measurements"
	osnd_moon_teardown 2>/dev/null
	for pid in "${pids[@]}"; do
		kill $pid &>/dev/null
	done
	_osnd_moon_cleanup
}

# _osnd_moon_interrupt_measurements()
# Trap function executed when the SIGINT signal is received
function _osnd_moon_interrupt_measurements() {
	# Don't just stop the current command, exit the entire script instead
	exit 1
}

# _osnd_moon_check_running_emulation()
function _osnd_moon_check_running_emulation() {
	# Check for running tmux sessions
	if [ ! tmux -L ${TMUX_SOCKET} list-sessions ] &>/dev/null; then
		echo >&2 "Active tmux sessions found!"
		echo >&2 "Another emulation might already be running, or this is a leftover of a previous run."
		echo >&2 "Execute the ./teardown.sh script to get rid of any leftovers."
		exit 2
	fi

	# Check if namespaces exist
	for ns in $(sudo ip netns list); do
		if [[ "$ns" == "osnd"* ]]; then
			echo >&2 "Existing namespace $ns!"
			echo >&2 "Another emulation might already be running, or this is a leftover of a previous run."
			echo >&2 "Execute the ./teardown.sh script to get rid of any leftovers."
			exit 3
		fi
	done
}

# _osnd_moon_create_emulation_output_dir()
function _osnd_moon_create_emulation_output_dir() {
	log D "Creating output directory"

	if [ -e "$EMULATION_DIR" ]; then
		echo >&2 "Output directory $EMULATION_DIR already exists"
		exit 4
	fi

	mkdir -p "$EMULATION_DIR"
	if [ $? -ne 0 ]; then
		echo >&2 "Failed to create output directory $EMULATION_DIR"
		exit 5
	fi

	# Create 'latest' symlink
	local latest_link="$RESULTS_DIR/latest"
	if [ -h "$latest_link" ]; then
		rm "$latest_link"
	fi
	if [ ! -e "$latest_link" ]; then
		ln -s "$EMULATION_DIR" "$latest_link"
	fi
}

# _osnd_moon_create_emulation_tmp_dir()
function _osnd_moon_create_emulation_tmp_dir() {
	log D "Creating temporary directory"

	local tmp_dir=$(mktemp -d --tmpdir opensand-moongen.XXXXXX)
	if [ "$?" -ne 0 ]; then
		echo >&2 "Failed to create temporary directory"
		exit 6
	fi

	export OSND_TMP="$tmp_dir"
	export OSND_MOON_TMP="${OSND_TMP}"
}

# _osnd_moon_start_logging_pipe()
# Creates a named pipe to be used by processes in tmux sessions to output log messages
function _osnd_moon_start_logging_pipe() {
	log D "Starting log pipe"
	mkfifo "${OSND_MOON_TMP}/logging"
	tail -f -n +0 "${OSND_MOON_TMP}/logging" > >(log -) &
	pids['logpipe']=$!
}

# _osnd_moon_stop_logging_pipe()
function _osnd_moon_stop_logging_pipe() {
	log D "Stopping log pipe"
	kill ${pids['logpipe']} &>/dev/null
	unset pids['logpipe']
	rm "${OSND_MOON_TMP}/logging"
}

# _osnd_moon_generate_scenarios()
function _osnd_moon_generate_scenarios() {
	scenario_file="$OSND_MOON_TMP/scenarios"
	echo "# Scenario config generated at $(date)" >"$scenario_file"

	local common_options="-N ${run_cnt} -T ${ttfb_run_cnt} -P ${env_prime_secs} -D ${dump_packets}"
	if [[ "$exec_plain" != "true" ]]; then
		common_options="$common_options -V"
	fi
	if [[ "$exec_pep" != "true" ]]; then
		common_options="$common_options -W"
	fi
	if [[ "$exec_ping" != "true" ]]; then
		common_options="$common_options -X"
	fi
	if [[ "$exec_quic" != "true" ]]; then
		common_options="$common_options -Y"
	fi
	if [[ "$exec_tcp" != "true" ]]; then
		common_options="$common_options -Z"
	fi
	if [[ "$exec_http" != "true" ]]; then
		common_options="$common_options -H"
	fi
	if [[ ${#qlog_file} -le 0 ]]; then
		qlog_file="${EMULATION_DIR}/client.qlog,${EMULATION_DIR}/server.qlog"
	fi

	for orbit in "${orbits[@]}"; do
		for attenuation in "${attenuations[@]}"; do
			for ccs in "${cc_algorithms[@]}"; do
				for tbs in "${transfer_buffer_sizes[@]}"; do
					for qbs in "${quicly_buffer_sizes[@]}"; do
						for ubs in "${udp_buffer_sizes[@]}"; do
							for delay in "${delays[@]}"; do
								for loss in "${packet_losses[@]}"; do
									for iw in "${iws[@]}"; do
										for ack_freq in "${ack_freqs[@]}"; do
											for bw in "${iperf_bw[@]}"; do
												for route in "${routing_strategy[@]}"; do
													for gds in "${ground_delays[@]}"; do
														for mp_ccs in "${mptcp_cc_algorithms[@]}"; do
															for mp_pm in "${mptcp_path_managers[@]}"; do
																for mp_sched in "${mptcp_schedulers[@]}"; do
																	local scenario_options="-O ${orbit} -A ${attenuation} -C ${ccs} -B ${tbs} -Q ${qbs} -U ${ubs} -E ${delay} -L ${loss} -I ${iw} -F ${ack_freq} -l ${qlog_file} -b ${bw} -r ${route} -g ${gds} -c ${mp_ccs} -p ${mp_pm} -S ${mp_sched}"
																	echo "$common_options $scenario_options" >>"$scenario_file"
																done
															done
														done
													done
												done
											done
										done
									done
								done
							done
						done
					done
				done
			done
		done
	done
}

# _osnd_moon_count_scenarios()
function _osnd_moon_count_scenarios() {
	awk '!/^(#.*)?$/' "$scenario_file" | wc -l
}

# _osnd_moon_read_scenario(config_ref, scenario)
function _osnd_moon_read_scenario() {
	local -n config_ref="$1"
	local scenario="$2"

	local parsed_scenario_args=$(getopt -n "opensand-moongen scenario" -o "A:b:B:c:C:D:E:F:g:HI:M:N:l:L:N:O:p:P:Q:r:S:T:U:VWXYZ" -l "attenuation:,iperf-bandwidth:,transport-buffers:,mptcp-congestion-control:,congestion-control:,dump:,delay:,ack-frequency:,ground-delays:,disable-http,initial-window:,modulation:,runs:,qlog-file:,loss:,orbit:,mptcp-path-manager:,prime:,quicly-buffers:,routing-strategy:,mptcp-scheduler,timing-runs:,udp-buffers:,udp-buffers:,disable-plain,disable-pep,disable-ping,disable-quic,disable-tcp" -- $scenario)
	local parsing_status=$?
	if [ "$parsing_status" != "0" ]; then
		return 1
	fi

	set +o nounset
	eval set -- "$parsed_scenario_args"
	while :; do
		case "$1" in
		-A | --attenuation)
			config_ref['attenuation']="$2"
			shift 2
			;;
		-b | --iperf-bandwidth)
			config_ref['bw']="$2"
			shift 2
			;;
		-B | --transport-buffers)
			config_ref['tbs']="$2"
			shift 2
			;;
		-c | --mptcp-congestion-control)
			config_ref['mp_cc']="$2"
			shift 2
			;;
		-C | --congestion-control)
			config_ref['ccs']="$2"
			shift 2
			;;
		-D | --dump)
			config_ref['dump']="$2"
			shift 2
			;;
		-E | --delay)
			config_ref['delay']="$2"
			shift 2
			;;
		-F | --ack-frequency)
			config_ref['ack_freq']="$2"
			shift 2
			;;
		-g | --ground-delays)
			config_ref['gds']="$2"
			shift 2
			;;
		-H | --disable-http)
			config_ref['exec_http']="false"
			shift 1
			;;
		-I | --initial-window)
			config_ref['iw']="$2"
			shift 2
			;;
		-M | --modulation)
			config_ref['modulation_id']="$2"
			shift 2
			;;
		-N | --runs)
			config_ref['runs']="$2"
			shift 2
			;;
		-l | --qlog-file)
			config_ref['qlog_file']="$2"
			shift 2
			;;
		-L | --loss)
			config_ref['loss']="$2"
			shift 2
			;;
		-O | --orbit)
			config_ref['orbit']="$2"
			shift 2
			;;
		-p | --mptcp-path-manager)
			config_ref['mp_pm']="$2"
			shift 2
			;;
		-P | --prime)
			config_ref['prime']="$2"
			shift 2
			;;
		-Q | --quicly-buffers)
			config_ref['qbs']="$2"
			shift 2
			;;
		-r | --routing-strategy)
			config_ref['route']="$2"
			shift 2
			;;
		-S | --mptcp-scheduler)
			config_ref['mp_sched']="$2"
			shift 2
			;;
		-T | --timing-runs)
			config_ref['timing_runs']="$2"
			shift 2
			;;
		-U | --udp-buffers)
			config_ref['ubs']="$2"
			shift 2
			;;
		-V | --disable-plain)
			config_ref['exec_plain']="false"
			shift 1
			;;
		-W | --disable-pep)
			config_ref['exec_pep']="false"
			shift 1
			;;
		-X | --disable-ping)
			config_ref['exec_ping']="false"
			shift 1
			;;
		-Y | --disable-quic)
			config_ref['exec_quic']="false"
			shift 1
			;;
		-Z | --disable-tcp)
			config_ref['exec_tcp']="false"
			shift 1
			;;
		--)
			# Stop parsing args
			shift 1
			break
			;;
		*)
			echo >&2 "Unknown argument while reading scenario: $1"
			return 2
			;;
		esac
	done
	set -o nounset
}

# _osnd_moon_exec_scenario_with_config(config_name)
function _osnd_moon_exec_scenario_with_config() {
	local config_name="$1"
	local -n config_ref="$1"

	# Create output directory for measurements in this configuration
	local measure_output_dir="${EMULATION_DIR}/${config_ref['id']}"
	if [ -d "$measure_output_dir" ]; then
		log W "Output directory $measure_output_dir already exists"
	fi
	mkdir -p "$measure_output_dir"

	# Save configuration
	{
		echo "script_version=${SCRIPT_VERSION}"
		for config_key in "${!config_ref[@]}"; do
			echo "${config_key}=${config_ref[$config_key]}"
		done
	} | sort >"$measure_output_dir/config.txt"

	local run_cnt=${config_ref['runs']:-1}
	local run_timing_cnt=${config_ref['timing_runs']:-2}
	local sel_route=${config_ref['route']:-"LTE"}

	if [[ "${config_ref['route']:-"LTE"}" == "LTE" ]]; then
		config_ref['exec_pep']=false
	fi

	if [[ "${config_ref['route']:-"LTE"}" == "MP" ]]; then
		config_ref['exec_quic']=false
		config_ref['exec_http']=false
	fi

	if [[ "${config_ref['exec_ping']:-true}" == true ]]; then
		osnd_moon_measure_ping "$config_name" "$measure_output_dir" "$sel_route"
	fi

	if [[ "${config_ref['exec_quic']:-true}" == true ]]; then
		if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
			osnd_moon_measure_quic_goodput "$config_name" "$measure_output_dir" false "$sel_route" $run_cnt
			osnd_moon_measure_quic_timing "$config_name" "$measure_output_dir" false "$sel_route" $run_timing_cnt
		fi
		if [[ "${config_ref['exec_pep']:-true}" == true ]]; then
			osnd_moon_measure_quic_goodput "$config_name" "$measure_output_dir" true "$sel_route" $run_cnt
			osnd_moon_measure_quic_timing "$config_name" "$measure_output_dir" true "$sel_route" $run_timing_cnt
		fi
	fi

	if [[ "${config_ref['exec_tcp']:-true}" == true ]]; then
		if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
			osnd_moon_measure_tcp_goodput "$config_name" "$measure_output_dir" false "$sel_route" $run_cnt
			osnd_moon_measure_tcp_timing "$config_name" "$measure_output_dir" false "$sel_route" $run_timing_cnt
		fi
		if [[ "${config_ref['exec_pep']:-true}" == true ]]; then
			osnd_moon_measure_tcp_goodput "$config_name" "$measure_output_dir" true "$sel_route" $run_cnt
			osnd_moon_measure_tcp_timing "$config_name" "$measure_output_dir" true "$sel_route" $run_timing_cnt
		fi
	fi

	if [[ "${config_ref['exec_http']:-true}" == true ]]; then
		if [[ "${config_ref['exec_tcp']:-true}" == true ]]; then
			if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
				osnd_moon_measure_http "$config_name" "$measure_output_dir" false "$sel_route" $run_cnt false
			fi
			if [[ "${config_ref['exec_pep']:-false}" == true ]]; then
				osnd_moon_measure_http "$config_name" "$measure_output_dir" true "$sel_route" $run_cnt false
			fi
		fi
		if [[ "${config_ref['exec_quic']:-true}" == true ]]; then
			if [[ "${config_ref['exec_plain']:-true}" == true ]]; then
				osnd_moon_measure_http "$config_name" "$measure_output_dir" false "$sel_route" $run_cnt true
			fi
			if [[ "${config_ref['exec_pep']:-true}" == true ]]; then
				osnd_moon_measure_http "$config_name" "$measure_output_dir" true "$sel_route" $run_cnt true
			fi
		fi
	fi
}

#_osnd_moon_get_cc(ccs, index)
function _osnd_moon_get_cc() {
	local ccs="$1"
	local index=$2

	case ${ccs:$index:1} in
	c | C)
		echo "cubic"
		;;
	r | R)
		echo "reno"
		;;
	esac
}

# _osnd_moon_run_scenarios()
function _osnd_moon_run_scenarios() {
	local measure_cnt=$(_osnd_moon_count_scenarios)
	local measure_nr=0

	env | sort >"${EMULATION_DIR}/environment.txt"

	while read scenario; do
		((measure_nr++))
		log I "Starting measurement ${measure_nr}/${measure_cnt}"
		log D "Reading scenario: $scenario"

		unset scenario_config
		declare -A scenario_config

		# Default configuration values
		scenario_config['exec_plain']="true"
		scenario_config['exec_pep']="true"
		scenario_config['exec_ping']="true"
		scenario_config['exec_quic']="true"
		scenario_config['exec_tcp']="true"
		scenario_config['exec_http']="true"

		scenario_config['prime']=5
		scenario_config['runs']=1
		scenario_config['timing_runs']=4
		scenario_config['dump']=0

		scenario_config['orbit']="GEO"
		scenario_config['attenuation']=0
		scenario_config['modulation_id']=1
		scenario_config['ccs']="rrrr"
		scenario_config['tbs']="1M,1M"
		scenario_config['qbs']="1M,1M,1M,1M"
		scenario_config['ubs']="1M,1M,1M,1M"
		scenario_config['delay']="125,125"
		scenario_config['loss']=0
		scenario_config['iw']="10,10,10,10"
		scenario_config['ack_freq']="25,1000,8"
		scenario_config['qlog_file']="${EMULATION_DIR}/client.qlog,${EMULATION_DIR}/server.qlog"

		scenario_config['bw']="20M,5M"
		scenario_config['route']="LTE"
		scenario_config['gds']="0,0,0"

		scenario_config['mp_cc']="lia"
		scenario_config['mp_pm']="fullmesh"
		scenario_config['mp_sched']="default"

		_osnd_moon_read_scenario scenario_config "$scenario"
		local read_status=$?
		if [ "$read_status" != "0" ]; then
			log E "Failed to read scenario($read_status): '$scenario'"
			sleep $MEASURE_WAIT
			continue
		fi
		scenario_config['id']="$(md5sum <<<"$scenario" | cut -d' ' -f 1)"

		# Extract combined values
		scenario_config['cc_sv']="$(_osnd_moon_get_cc "${scenario_config['ccs']}", 0)"
		scenario_config['cc_gw']="$(_osnd_moon_get_cc "${scenario_config['ccs']}", 1)"
		scenario_config['cc_st']="$(_osnd_moon_get_cc "${scenario_config['ccs']}", 2)"
		scenario_config['cc_cl']="$(_osnd_moon_get_cc "${scenario_config['ccs']}", 3)"

		local -a tbuf_sizes=()
		IFS=',' read -ra tbuf_sizes <<<"${scenario_config['tbs']}"
		scenario_config['tbs_gw']="${tbuf_sizes[0]}"
		scenario_config['tbs_st']="${tbuf_sizes[1]}"

		local -a qbuf_sizes=()
		IFS=',' read -ra qbuf_sizes <<<"${scenario_config['qbs']}"
		scenario_config['qbs_sv']="${qbuf_sizes[0]}"
		scenario_config['qbs_gw']="${qbuf_sizes[1]}"
		scenario_config['qbs_st']="${qbuf_sizes[2]}"
		scenario_config['qbs_cl']="${qbuf_sizes[3]}"

		local -a ubuf_sizes=()
		IFS=',' read -ra ubuf_sizes <<<"${scenario_config['ubs']}"
		scenario_config['ubs_sv']="${ubuf_sizes[0]}"
		scenario_config['ubs_gw']="${ubuf_sizes[1]}"
		scenario_config['ubs_st']="${ubuf_sizes[2]}"
		scenario_config['ubs_cl']="${ubuf_sizes[3]}"

		local -a delays=()
		IFS=',' read -ra delays <<<"${scenario_config['delay']}"
		scenario_config['delay_gw']="${delays[0]}"
		scenario_config['delay_st']="${delays[1]}"

		local -a iw_sizes=()
		IFS=',' read -ra iw_sizes <<<"${scenario_config['iw']}"
		scenario_config['iw_sv']="${iw_sizes[0]}"
		scenario_config['iw_gw']="${iw_sizes[1]}"
		scenario_config['iw_st']="${iw_sizes[2]}"
		scenario_config['iw_cl']="${iw_sizes[3]}"

		local -a ack_freq_params=()
		IFS=',' read -ra ack_freq_params <<<"${scenario_config['ack_freq']}"
		scenario_config['max_ack_delay']="${ack_freq_params[0]}"
		scenario_config['first_ack_freq_packet_number']="${ack_freq_params[1]}"
		scenario_config['ack_freq_cwnd_fraction']="${ack_freq_params[2]}"

		local -a qlog_files=()
		IFS=',' read -ra qlog_files <<<"${scenario_config['qlog_file']}"
		scenario_config['qlog_file_client']="${qlog_files[0]}"
		scenario_config['qlog_file_server']="${qlog_files[1]}"

		local -a bw_vals=()
		IFS=',' read -ra bw_vals <<<"${scenario_config['bw']}"
		scenario_config['bw_ul']="${bw_vals[0]}"
		scenario_config['bw_dl']="${bw_vals[1]}"

		local -a gd_vals=()
		IFS=',' read -ra gd_vals <<<"${scenario_config['gds']}"
		scenario_config['delay_cl_sat']="${gd_vals[0]}"
		scenario_config['delay_cl_lte']="${gd_vals[1]}"
		scenario_config['delay_sv']="${gd_vals[2]}"

		# Execute scenario
		echo "${scenario_config['id']} $scenario" >>"${EMULATION_DIR}/scenarios.txt"
		_osnd_moon_exec_scenario_with_config scenario_config

		sleep $MEASURE_WAIT
	done < <(awk '!/^(#.*)?$/' "$scenario_file")
}

# _osnd_moon_print_usage()
function _osnd_moon_print_usage() {
	cat <<USAGE
Usage: $1 [options]
General:
  -f <file>  read the scenarios from this file instead of the command line arguments.
  -h         print this help message
  -s         show statistic logs in stdout
  -t <tag>   optional tag to identify this measurement
  -v         print version and exit
Scenario configuration:
  -A <#,>    csl of attenuations to measure (default: 0db)
  -B <#,>*   QUIC-specific: csl of two qperf transfer buffer sizes for G and T (default: 1M)
  -b <#,>	 iPerf bandwith vis-à-vis the defined QoS requirements [UL/DL] (default: 20M,5M)
  -c <#,>	 MPTCP-specific: congestion control (lia, olia, balia, wVegas) (default: lia)
  -C <SGTC,> csl of congestion control algorithms to measure (c = cubic, r = reno) (default: r)
  -D #       dump the first # packets of a measurement
  -E <GT,>   csl of two delay values: each one value or multiple seconds-delay values (default: 125)
  -g <#,>	 csl of ground delays at the client and the server [CL_SAT,CL_LTE,SV] (default: 0,0,0)
  -H         disable http measurements
  -F <#,>*   QUIC-specific: csl of three values: max. ACK Delay, packet no. after which first ack frequency packet is sent, fraction of CWND to be used in ACK frequency frame (default: 25, 1000, 8)
  -I <#,>*   csl of four initial window sizes for SGTC (default: 10)
  -l <#,>    QUIC-specific: csl of two file paths for qlog file output: client, server (default: server.qlog und client.qlog in output directory) 
  -L <#,>    percentages of packets to be dropped (default: 0%)
  -N #       number of goodput measurements per config (default: 1)
  -O <#,>    csl of orbits to measure (GEO|MEO|LEO) (default: GEO)
  -p <#,>	 MPTCP-specific: advanced path-manager control (default, fullmesh, binder, netlink) (default: fullmesh) 
  -P #       seconds to prime a new environment with some pings (default: 5)
  -Q <#,>*   QUIC-specific: csl of four qperf quicly buffer sizes for SGTC (default: 1M)
  -r <#,>	 Select a routing strategy (LTE|SAT|MP) (default: LTE)
  -S <#,> 	 MPTCP-specific: scheduler (default, roundrobin, redundant, blest) (default: default)
  -T #       number of timing measurements per config (default: 4)
  -U <#,>*   QUIC-specific: csl of four qperf udp buffer sizes for SGTC (default: 1M)
  -V         disable plain (non pep) measurements
  -W         disable pep measurements
  -X         disable ping measurement
  -Y         disable quic measurements
  -Z         disable tcp measurements
Scenario file format:
  Each line in the file describes a single scenario, blank lines and lines
  starting with a # are ignored. A scenario can be configured using the arguments
  in the scenario configuration section above. However all arguments that accept
  a comma separated list of values only accept a single value in the scenario
  file. Same goes for the repeated arguments, only one value is accepted.
<#,> indicates that the argument accepts a comma separated list (csl) of values
...* indicates, that the argument can be repeated multiple times
SGTC specifies one value for each of the emulation components:
     server, gateway, satellite terminal and client
USAGE
}

function _osnd_moon_parse_args() {
	show_stats=false
	osnd_moon_tag=""
	env_prime_secs=5
	ttfb_run_cnt=4
	run_cnt=1
	exec_plain=true
	exec_pep=true
	exec_ping=true
	exec_quic=true
	exec_tcp=true
	exec_http=true
	scenario_file=""
	dump_packets=0
	qlog_file=""

	local -a new_transfer_buffer_sizes=()
	local -a new_quicly_buffer_sizes=()
	local -a new_udp_buffer_sizes=()
	local -a new_delays=()
	local -a new_quicly_iw_sizes=()
	local -a new_quicly_ack_freq=()
	local -a new_iperf_bw=()
	local -a new_ground_delays=()
	local measure_cli_args="false"
	while getopts "b:c:f:g:hl:p:r:st:vA:B:C:D:E:F:HI:L:N:O:P:Q:S:T:U:VWXYZ" opt; do
		if [[ "${opt^^}" == "$opt" ]]; then
			measure_cli_args="true"
			if [[ "$scenario_file" != "" ]]; then
				echo >&2 "Cannot configure measurements with cli args when scenario file is given"
				exit 1
			fi
		fi

		case "$opt" in
		b)
			IFS=',' read -ra bw_vals <<<"$OPTARG"
			if [[ "${#bw_vals[@]}" != 2 ]]; then
				echo "Need exactly two bandwith values for UL and DL, respectively, ${#bw_vals[@]} given in '$OPTARG'"
				exit 1
			fi
			new_iperf_bw+=("$OPTARG")
			;;
		c)
			IFS=',' read -ra mptcp_cc_algorithms <<<"$OPTARG"
			;;
		f)
			if [[ "$measure_cli_args" == "true" ]]; then
				echo >&2 "Cannot set scenario file and configure measurements with cli args at the same time"
				exit 1
			fi
			scenario_file="$OPTARG"
			;;
		g)
			IFS=',' read -ra gd_vals <<<"$OPTARG"
			if [[ "${#gd_vals[@]}" != 3 ]]; then
				echo "Need exactly three ground delay values, ${#gd_vals[@]} given in '$OPTARG'"
				exit 1
			else
				for ground_delay in "${gd_vals[@]}"; do
					if ! [[ "${ground_delay}" =~ ^[0-9]+$ ]]; then
						echo "Invalid integer value for -g"
						exit 1
					fi
				done
			fi
			new_ground_delays+=("$OPTARG")
			;;
		h)
			_osnd_moon_print_usage "$0"
			exit 0
			;;
		l)
			IFS=',' read -ra qlog_files <<<"$OPTARG"
			if [[ "${#qlog_files[@]}" != 2 ]]; then
				echo "Need exactly two files, ${#qlog_files[@]} given in '$OPTARG'"
				exit 1
			fi
			qlog_file=$OPTARG
			;;
		p)
			IFS=',' read -ra mptcp_path_managers <<<"$OPTARG"
			;;
		r)
			IFS=',' read -ra routing_strategy <<<"$OPTARG"
			;;
		s)
			show_stats=true
			;;
		t)
			osnd_moon_ytag="_$OPTARG"
			;;
		v)
			echo "opensand-moongen-measurement $SCRIPT_VERSION"
			exit 0
			;;
		A)
			IFS=',' read -ra attenuations <<<"$OPTARG"
			;;
		B)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 2 ]]; then
				echo "Need exactly two transfer buffer size configurations for G and T, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_transfer_buffer_sizes+=("$OPTARG")
			;;
		C)
			IFS=',' read -ra cc_algorithms <<<"$OPTARG"
			for ccs in "${cc_algorithms[@]}"; do
				if [[ "${#ccs}" != 4 ]]; then
					echo "Need exactly four cc algorithms for SGT, ${#ccs} given in '$ccs'"
					exit 1
				fi
				for i in 0 1 2 3; do
					if [[ "$(_osnd_moon_get_cc "$ccs" $i)" == "" ]]; then
						echo "Unknown cc algorithm '${ccs:$i:1}' in '$ccs'"
						exit 1
					fi
				done
			done
			;;
		D)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				dump_packets=$OPTARG
			else
				echo "Invalid integer value for -D"
				exit 1
			fi
			;;
		E)
			IFS=',' read -ra delay_values <<<"$OPTARG"
			if [[ "${#delay_values[@]}" != 2 ]]; then
				echo "Need exactly two delay values, ${#delay_values[@]} given in '${delay_values[@]}'"
				exit 1
			else
				for delay in "${delay_values[@]}"; do
					IFS=';' read -ra procDelays <<<"${delay}"
					if [[ "${#procDelays[@]}" == 1 ]]; then
						if ! [[ "${procDelays[0]}" =~ ^[0-9]+$ ]]; then
							echo "Invalid integer value for -E"
							exit 1
						fi
					else
						for delayFileLine in "${procDelays[@]}"; do
							IFS='-' read -ra procDelayFileLine <<<"${delayFileLine}"
							if [[ "${#procDelayFileLine[@]}" != 2 ]]; then
								echo "Invalid integer value for -E"
								exit 1
							fi
							for procDelayFileLine in "${procDelayFileLine[@]}"; do
								if ! [[ "${procDelayFileLine}" =~ ^[0-9]+$ ]]; then
									echo "Invalid integer value for -E"
									exit 1
								fi
							done
						done
					fi
				done
			fi
			new_delays+=("$OPTARG")
			;;
		F)
			IFS=',' read -ra ack_freq_values <<<"$OPTARG"
			if [[ "${#ack_freq_values[@]}" != 3 ]]; then
				echo "Need exactly three ack frequency values, ${#ack_freq_values[@]} given in '${ack_freq_values[@]}'"
				exit 1
			else
				for ack_freq in "${ack_freq_values[@]}"; do
					if ! [[ "${ack_freq}" =~ ^[0-9]+$ ]]; then
						echo "Invalid integer value for -F"
						exit 1
					fi
				done
				if [[ ack_freq_values[1] -gt 65535 ]]; then
					echo "First packet number has the type uint16 and cannot be larger than 65535"
					exit 1
				fi
				if [[ ack_freq_values[2] -gt 255 ]]; then
					echo "CWND fraction has the type uint8 and cannot be larger than 255"
					exit 1
				fi
			fi
			new_quicly_ack_freq+=("$OPTARG")
			;;
		H)
			exec_http=false
			;;
		I)
			IFS=',' read -ra iw_sizes_config <<<"$OPTARG"
			if [[ "${#iw_sizes_config[@]}" != 4 ]]; then
				echo "Need exactly four initial window configurations for SGTC, ${#iw_sizes_config[@]} given in '$OPTARG'"
				exit 1
			else
				for iw in "${iw_sizes_config[@]}"; do
					if ! [[ "${iw}" =~ ^[0-9]+$ ]]; then
						echo "Invalid integer value for -I"
						exit 1
					fi
				done
			fi
			new_quicly_iw_sizes+=("$OPTARG")
			;;
		L)
			IFS=',' read -ra packet_losses <<<"$OPTARG"
			for loss in "${packet_losses[@]}"; do
				if ! [[ "${loss}" =~ ^[0-9]+(.[0-9]+)?$ ]]; then
					echo "Invalid float value for -L"
					exit 1
				fi
			done
			;;
		N)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				run_cnt=$OPTARG
			else
				echo "Invalid integer value for -N"
				exit 1
			fi
			;;
		O)
			IFS=',' read -ra orbits <<<"$OPTARG"
			;;
		P)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				env_prime_secs=$OPTARG
			else
				echo "Invalid integer value for -P"
				exit 1
			fi
			;;
		Q)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 4 ]]; then
				echo "Need exactly four quicly buffer size configurations for SGTC, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_quicly_buffer_sizes+=("$OPTARG")
			;;
		S)
			IFS=',' read -ra mptcp_schedulers <<<"$OPTARG"
			;;
		T)
			if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				ttfb_run_cnt=$OPTARG
			else
				echo "Invalid integer value for -T"
				exit 1
			fi
			;;
		U)
			IFS=',' read -ra buffer_sizes_config <<<"$OPTARG"
			if [[ "${#buffer_sizes_config[@]}" != 4 ]]; then
				echo "Need exactly four udp buffer size configurations for SGTC, ${#buffer_sizes_config[@]} given in '$OPTARG'"
				exit 1
			fi
			new_udp_buffer_sizes+=("$OPTARG")
			;;
		V)
			exec_plain=false
			;;
		W)
			exec_pep=false
			;;
		X)
			exec_ping=false
			;;
		Y)
			exec_quic=false
			;;
		Z)
			exec_tcp=false
			;;
		:)
			echo "Argumet required for -$OPTARG" >&2
			echo "$0 -h for help" >&2
			exit 1
			;;
		?)
			echo "Unknown argument -$OPTARG" >&2
			echo "$0 -h for help" >&2
			exit 2
			;;
		esac
	done

	if [[ "${#new_transfer_buffer_sizes[@]}" > 0 ]]; then
		transfer_buffer_sizes=("${new_transfer_buffer_sizes[@]}")
	fi
	if [[ "${#new_quicly_buffer_sizes[@]}" > 0 ]]; then
		quicly_buffer_sizes=("${new_quicly_buffer_sizes[@]}")
	fi
	if [[ "${#new_udp_buffer_sizes[@]}" > 0 ]]; then
		udp_buffer_sizes=("${new_udp_buffer_sizes[@]}")
	fi
	if [[ "${#new_delays[@]}" > 0 ]]; then
		delays=("${new_delays[@]}")
	fi
	if [[ "${#new_quicly_iw_sizes[@]}" > 0 ]]; then
		iws=("${new_quicly_iw_sizes[@]}")
	fi
	if [[ "${#new_quicly_ack_freq[@]}" > 0 ]]; then
		ack_freqs=("${new_quicly_ack_freq[@]}")
	fi
	if [[ "${#new_iperf_bw[@]}" > 0 ]]; then
		iperf_bw=("${new_iperf_bw[@]}")
	fi
	if [[ "${#new_ground_delays[@]}" > 0 ]]; then
		ground_delays=("${new_ground_delays[@]}")
	fi
}

function _main() {
	declare -a orbits=("GEO")
	declare -a attenuations=(0)
	declare -a cc_algorithms=("rrrr")
	declare -a transfer_buffer_sizes=("1M,1M")
	declare -a quicly_buffer_sizes=("1M,1M,1M,1M")
	declare -a udp_buffer_sizes=("1M,1M,1M,1M")
	declare -a delays=("125,125")
	declare -a packet_losses=(0)
	declare -a iws=("10,10,10,10")
	declare -a ack_freqs=("25,1000,8")
	declare -a iperf_bw=("20M,5M")
	declare -a routing_strategy=("LTE")
	declare -a ground_delays=("0,0,0")
	declare -a mptcp_schedulers=("default")
	declare -a mptcp_cc_algorithms=("lia")
	declare -a mptcp_path_managers=("fullmesh")

	_osnd_moon_parse_args "$@"

	_osnd_moon_check_running_emulation

	emulation_start="$(date +"%Y-%m-%d-%H-%M")"
	export EMULATION_DIR="${RESULTS_DIR}/${emulation_start}_opensand_moongen${osnd_moon_tag}"
	_osnd_moon_create_emulation_output_dir
	_osnd_moon_create_emulation_tmp_dir

	if [[ "$scenario_file" == "" ]]; then
		_osnd_moon_generate_scenarios
	fi

	log I "Starting Opensand-Moongen satellite-lte emulation measurements"
	# Start printing stats
	osnd_stats_every 4 &
	pids['stats']=$!
	_osnd_moon_start_logging_pipe

	trap _osnd_moon_abort_measurements EXIT
	trap _osnd_moon_interrupt_measurements SIGINT

	_osnd_moon_run_scenarios 2> >(log E -)

	trap - SIGINT
	trap - EXIT

	log I "All measurements are done, cleaning up"

	_osnd_moon_stop_logging_pipe
	kill ${pids['stats']} &>/dev/null
	unset pids['stats']

	_osnd_moon_cleanup
	log I "Done with all measurements"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_main "$@"
fi
