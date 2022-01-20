#!/bin/bash

# moon_setup_moongen()
function moon_setup_moongen() {
    local output_dir="${1:-.}"
    local run_id="${2:-manual}"

    # Start MoonGen LTE emulation
    log D "Emulating LTE link with defaults"
    sudo killall lte-emulation -q
    tmux -L ${TMUX_SOCKET} new-session -s lte-emulation -d "sudo bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t lte-emulation "sudo ${MOONGEN_BIN} ${MOONGEN_SCRIPT_DIR}/${MOONGEN_SCRIPT} -d ${DEV_0} ${DEV_1} -r ${RATE_DL} ${RATE_UL} -l ${LATENCY_DL} ${LATENCY_UL} -q ${QDEPTH_DL} ${QDEPTH_UL} -u ${CATCHUP_RATE_DL} ${CATCHUP_RATE_UL} -c ${CONCEALED_LOSS_DL} ${CONCEALED_LOSS_UL} -o ${LOSS_DL} ${LOSS_UL} --ho_pcm ${HO_PCM} --ho_frequency ${HO_FREQ_MEAN} ${HO_FREQ_VARIANCE} > '${output_dir}/${run_id}_moongen.log'" Enter
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    source "${CONFIG_DIR}/moon-config.sh"
    set +a

    moon_setup_moongen "$@"
fi
