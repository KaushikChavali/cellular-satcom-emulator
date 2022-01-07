#!/bin/bash

# moon_setup_moongen()
function moon_setup_moongen() {
    local output_dir="${2:-.}"
    local run_id="${3:-manual}"

    # Start MoonGen LTE emulation
    log D "Emulating LTE link with defaults"
    sudo killall lte-emulation -q
    tmux -L ${TMUX_SOCKET} new-session -s lte-emulation -d "sudo bash"
    sleep $TMUX_INIT_WAIT
    tmux -L ${TMUX_SOCKET} send-keys -t lte-emulation "sudo ${MOONGEN_BIN} ${MOONGEN_SCRIPT_DIR}/lte-emulator-handover.lua > '${output_dir}/${run_id}_moongen.log'" Enter
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

    set -a
    source "${SCRIPT_DIR}/config/lte-config.sh"
    set +a

    moon_setup_moongen "$@"
fi
