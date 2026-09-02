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
usage: $(basename -- "$0") [run|self-test|check|tail|install-service] [options]

  run         hold the port open and forward messages (the default)
  self-test   send one test notification by email and SMS, then exit
  check       report the config, the port and whether anything holds it
  tail        follow the ledger, newest last
  install-service  write a systemd unit with this checkout's real paths

options:
  -c FILE     config file (default: ${DEFAULT_CONFIG})
  -d ID       device id for phone-book routing (self-test needs this)
  -n          dry run: log what would be sent, send nothing
  -v          verbose
  -s          install-service: system unit (starts at boot, no lingering)
              rather than a user unit

The config file carries a phone number and an email address. Keep it under
etc/secrets/, which is gitignored as a whole directory.
USAGE
}

CONFIG="${DEFAULT_CONFIG}"
ACTION='run'
SYSTEM_UNIT=0
declare -a PASSTHROUGH=()

case "${1:-}" in
    run | self-test | check | tail | install-service)
        ACTION="$1"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
esac

while getopts ':c:d:nvsh' opt; do
    case "${opt}" in
        c) CONFIG="${OPTARG}" ;;
        d) PASSTHROUGH+=('--device-id' "${OPTARG}") ;;
        n) PASSTHROUGH+=('--dry-run') ;;
        v) PASSTHROUGH+=('--verbose') ;;
        s) SYSTEM_UNIT=1 ;;
        h)
            usage
            exit 0
            ;;
        \?) die "unknown option: -${OPTARG}" ;;
        :) die "option -${OPTARG} requires an argument" ;;
    esac
done

if [[ ${ACTION} != 'install-service' ]]; then
    [[ -r ${CONFIG} ]] || die "cannot read config: ${CONFIG}
       Copy etc/listener.conf.example there and fill it in."
fi

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

if [[ ${ACTION} == 'install-service' ]]; then
    # Written rather than shipped verbatim, because the unit has to carry the
    # absolute path of *this* checkout. A committed unit with someone else's
    # home directory baked in is worse than no unit at all.
    unit_body() {
        cat <<UNIT
[Unit]
Description=Meshtastic listener for the attached radio
Documentation=file://${PROJECT_DIR}/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${PROJECT_DIR}
ExecStart=${SCRIPTS_DIR}/meshtastic-listener.sh run
${1}
# The board drops off the USB bus when it resets and returns a moment later.
# Restart rather than calling that a failure; the listener also reconnects on
# its own for as long as the process survives.
Restart=always
RestartSec=15

StandardOutput=journal
StandardError=journal
SyslogIdentifier=meshtastic-listener

[Install]
WantedBy=${2}
UNIT
    }

    if [[ ${SYSTEM_UNIT} -eq 1 ]]; then
        dest='/etc/systemd/system/meshtastic-listener.service'
        # Runs as the invoking user, never root: the ledger lives in the
        # checkout and root-owned files there break the next ordinary run.
        # dialout is what grants the serial port.
        body="$(unit_body "User=${USER}
Group=$(id -gn)
SupplementaryGroups=dialout" 'multi-user.target')"
        printf '%s\n' "${body}" | sudo tee "${dest}" >/dev/null
        sudo systemctl daemon-reload
        ok "installed ${dest}"
        info 'enable it with:  sudo systemctl enable --now meshtastic-listener'
        info 'follow it with:  journalctl -u meshtastic-listener -f'
    else
        dest="${HOME}/.config/systemd/user/meshtastic-listener.service"
        mkdir -p -- "$(dirname -- "${dest}")"
        unit_body '' 'default.target' >"${dest}"
        systemctl --user daemon-reload
        ok "installed ${dest}"
        info 'enable it with:  systemctl --user enable --now meshtastic-listener'
        info "survive logout:  sudo loginctl enable-linger ${USER}"
        info 'follow it with:  journalctl --user -u meshtastic-listener -f'
    fi
    exit 0
fi

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
