#!/bin/bash

# _osnd_moon_teardown_capture()
# Stop capturing packets
function _osnd_moon_teardown_capture() {
    local logged=false

    for entity in cl st gw sv; do
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

# osnd_moon_teardown()
# Teardown the entire emulation environment.
function osnd_moon_teardown() {
    log I "Tearing down emulation environment"
    osnd_teardown_opensand
    sleep $CMD_SHUTDOWN_WAIT
    moon_teardown_moongen
    sleep $CMD_SHUTDOWN_WAIT
    # _osnd_moon_teardown_capture
    osnd_teardown_namespaces
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
    set -a
    source "${SCRIPT_DIR}/quic-opensand-emulation/env.sh"
    source "${SCRIPT_DIR}/config/lte-config.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/teardown-opensand.sh"
    source "${SCRIPT_DIR}/quic-opensand-emulation/teardown-namespaces.sh"
    source "${SCRIPT_DIR}/teardown-moongen.sh"
    source "${SCRIPT_DIR}/teardown-lte-namespaces.sh"
    set +a

    osnd_moon_teardown "$@"

    # Ensure all tmux sessions are closed
    tmux -L ${TMUX_SOCKET} kill-server &>/dev/null

    if [ -e "$OSND_TMP" ]; then
        rm -rf "$OSND_TMP"
    fi
fi
