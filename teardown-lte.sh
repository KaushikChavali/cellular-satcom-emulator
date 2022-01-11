#!/bin/bash

# _moon_teardown_capture()
# Stop capturing packets
function _moon_teardown_capture() {
    local logged=false

    for entity in cl sv; do
        local session="tcpdump-${entity}"
        tmux -L ${TMUX_SOCKET} has-session -t ${session} >/dev/null 2>&1
        if [ "$?" -gt 0 ]; then
            if [[ "$logged" == false ]]; then
                log D "Stopping tcpdump"
                logged=true
            fi

            log D "Stopping $session"
            tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-c
            sleep $CMD_SHUTDOWN_WAIT
            tmux -L ${TMUX_SOCKET} send-keys -t ${session} C-d
            sleep $CMD_SHUTDOWN_WAIT
            tmux -L ${TMUX_SOCKET} kill-session -t ${session} >/dev/null 2>&1
        fi
    done
}

# moon_teardown()
# Teardown the entire emulation environment.
function moon_teardown() {
    log I "Tearing down emulation environment"
    moon_teardown_moongen
    sleep $CMD_SHUTDOWN_WAIT
    _moon_teardown_capture
    moon_teardown_namespaces
    log D "Environment teared down"
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    declare -F log >/dev/null || function log() {
        local level="$1"
        local msg="$2"

        echo "[$level] $msg"
    }

    export SCRIPT_VERSION="manual"
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    export CONFIG_DIR="${SCRIPT_DIR}/config"
    set -a
    source "${CONFIG_DIR}/testbed-config.sh"
    set +a
    source "${SCRIPT_DIR}/teardown-moongen.sh"
    source "${SCRIPT_DIR}/teardown-lte-namespaces.sh"

    osnd_teardown "$@"

    # Ensure all tmux sessions are closed
    tmux -L ${TMUX_SOCKET} kill-server &>/dev/null
fi
