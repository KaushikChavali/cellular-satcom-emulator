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
    source "${SCRIPT_DIR}/quic-opensand-emulation/env.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/teardown-opensand.sh"
    source "${SCRIPT_DIR}/teardown-moongen.sh"
    set +a

    osnd_teardown_opensand "$@"
    moon_teardown_moongen "$@"
fi
