#!/bin/bash

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
    source "${SCRIPT_DIR}/setup-moongen.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/env.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/setup-opensand.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/opensand.sh"
    set +a

    _osnd_create_emulation_output_dir
    _osnd_create_emulation_tmp_dir
    osnd_setup_opensand "$@"
    moon_setup_moongen "$@"
fi
