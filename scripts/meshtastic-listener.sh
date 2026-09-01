#!/usr/bin/env bash
#
# Run the Meshtastic message listener against the attached radio.
#
# Resolves the virtualenv holding the meshtastic library the same way the other
# scripts do, then hands off to scripts/meshtastic_listener.py.
#
# The radio serves one host at a time. This script refuses to start when
# something else already holds the serial port, because the failure mode
# otherwise is a silent non-response rather than an error.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/heltec-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/heltec-common.sh"

[[ ${EUID} -ne 0 ]] ||
    die "do not run this as root -- the ledger and any files it writes would
       become root-owned. Membership of group dialout is all that is needed."

cd -- "${PROJECT_DIR}"

readonly DEFAULT_CONFIG="${PROJECT_DIR}/etc/secrets/listener.conf"
readonly LISTENER_PY="${SCRIPTS_DIR}/meshtastic_listener.py"

usage() {
    cat <<USAGE
usage: $(basename -- "$0") [run|self-test|check|tail] [options]

  run         hold the port open and forward messages (the default)
  self-test   send one test notification by email and SMS, then exit
  check       report the config, the port and whether anything holds it
  tail        follow the ledger, newest last

options:
  -c FILE     config file (default: ${DEFAULT_CONFIG})
  -n          dry run: log what would be sent, send nothing
  -v          verbose

The config file carries a phone number and an email address. Keep it under
etc/secrets/, which is gitignored as a whole directory.
USAGE
}

CONFIG="${DEFAULT_CONFIG}"
ACTION='run'
declare -a PASSTHROUGH=()

case "${1:-}" in
    run | self-test | check | tail)
        ACTION="$1"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
esac

while getopts ':c:nvh' opt; do
    case "${opt}" in
        c) CONFIG="${OPTARG}" ;;
        n) PASSTHROUGH+=('--dry-run') ;;
        v) PASSTHROUGH+=('--verbose') ;;
        h)
            usage
            exit 0
            ;;
        \?) die "unknown option: -${OPTARG}" ;;
        :) die "option -${OPTARG} requires an argument" ;;
    esac
done

[[ -r ${CONFIG} ]] || die "cannot read config: ${CONFIG}
       Copy etc/listener.conf.example there and fill it in."

# --- ledger path, read from the config so `tail` and `check` agree with the
# --- daemon rather than guessing at it
ledger_path() {
    sed -nE 's/^[[:space:]]*ledger[[:space:]]*=[[:space:]]*(.+)$/\1/p' "${CONFIG}" |
        head -n 1
}

config_port() {
    sed -nE 's/^[[:space:]]*port[[:space:]]*=[[:space:]]*(.+)$/\1/p' "${CONFIG}" |
        head -n 1
}

if [[ ${ACTION} == 'tail' ]]; then
    LEDGER="$(ledger_path)"
    [[ -n ${LEDGER} ]] || die "no 'ledger' key in ${CONFIG}"
    [[ -e ${LEDGER} ]] || die "ledger does not exist yet: ${LEDGER}"
    exec tail -n 20 -f -- "${LEDGER}"
fi

VENV_BIN="$(resolve_venv_bin 'python')" || die "$(venv_hint)"
readonly VENV_BIN

"${VENV_BIN}/python" -c 'import meshtastic' 2>/dev/null ||
    die "the meshtastic library is not installed in ${VENV_BIN}.
       Install it with: ${VENV_BIN}/pip install meshtastic"

if [[ ${ACTION} == 'check' ]]; then
    section 'listener'
    ok "config      ${CONFIG}"
    ok "interpreter ${VENV_BIN}/python"
    PORT="$(config_port)"
    if [[ -z ${PORT} ]]; then
        fail '  no port in the config file'
    elif [[ -e ${PORT} ]]; then
        ok "port        ${PORT}"
        check_port_free "${PORT}"
    else
        fail "  port does not exist: ${PORT}"
        info '  a by-path name is the USB socket, not the board -- re-read it'
        info "  with ${SCRIPTS_DIR}/heltec-dev.sh ports after moving a radio"
    fi
    LEDGER="$(ledger_path)"
    if [[ -n ${LEDGER} && -e ${LEDGER} ]]; then
        ok "ledger      ${LEDGER} ($(wc -l <"${LEDGER}") records)"
    else
        info "ledger      ${LEDGER:-unset} (not created yet)"
    fi
    # report_result only returns a status; without an explicit exit this block
    # falls through and starts the listener, which is not what `check` means.
    report_result
    exit $?
fi

if [[ ${ACTION} == 'self-test' ]]; then
    PASSTHROUGH+=('--self-test')
else
    PORT="$(config_port)"
    if [[ -n ${PORT} && -e ${PORT} ]] && command -v fuser >/dev/null 2>&1; then
        HOLDERS="$(fuser "${PORT}" 2>/dev/null || true)"
        [[ -z ${HOLDERS//[[:space:]]/} ]] ||
            die "the serial port is already held by PID(s):${HOLDERS}
       The radio serves one host at a time. Stop that process first."
    fi
fi

exec "${VENV_BIN}/python" "${LISTENER_PY}" --config "${CONFIG}" "${PASSTHROUGH[@]}"
