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
    source "${SCRIPT_DIR}/quic-opensand-emulation/teardown-namespaces.sh"
    source "${SCRIPT_DIR}/teardown-lte-namespaces.sh"
    set +a

    osnd_teardown_namespaces "$@"
    moon_teardown_namespaces "$@"
fi
