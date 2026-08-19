#!/usr/bin/env bash
#
# Build, flash and monitor the Heltec WiFi LoRa 32 (V3). Run as the developer
# account, NOT as root: PlatformIO run as root leaves root-owned files in
# ~/.platformio and ./.pio that break the next build from a normal shell.
#
# Host setup (udev rule, dialout membership, ModemManager) is heltec-setup.sh,
# which does need root. This script only reads and writes the serial device,
# which group dialout already permits.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/heltec-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/heltec-common.sh"

[[ ${EUID} -ne 0 ]] ||
    die "do not run this as root -- it would leave root-owned files in
       ~/.platformio and ./.pio. Host setup lives in ${SCRIPTS_DIR}/heltec-setup.sh."

# PlatformIO resolves its project from the working directory, and pyenv resolves
# .python-version the same way. Anchor both to the project rather than to
# wherever the caller happened to be standing.
cd -- "${PROJECT_DIR}"

# --- interpreter -------------------------------------------------------------

# resolve_venv_bin() lives in lib/heltec-common.sh and accepts a pyenv
# virtualenv, a plain .venv in the checkout, an already-activated venv, or
# ${HELTEC_VENV}. See "Python environment" in README.md.
# Empty argument: any virtualenv with a python will do here. The esptool and
# meshtastic checks below report precisely which tool is missing.
VENV_BIN="$(resolve_venv_bin '')" || die "$(venv_hint)"
readonly VENV_BIN

# Prepending is harmless when the venv is already active, and is what makes
# this work when it is not.
PATH="${VENV_BIN}:${PATH}"
export PATH

# esptool 5 renamed the entry point from esptool.py to esptool; esptool 4 ships
# only the old name.
esptool_name() {
    if [[ -x "${VENV_BIN}/esptool" ]]; then
        printf 'esptool\n'
    elif [[ -x "${VENV_BIN}/esptool.py" ]]; then
        printf 'esptool.py\n'
    else
        return 1
    fi
}

esptool_major() {
    local tool
    tool="$(esptool_name)" || return 1
    # Matches both "esptool v5.3.1" and "esptool.py v4.11.0".
    "${VENV_BIN}/${tool}" version 2>/dev/null |
        sed -n 's/^esptool\(\.py\)\? v\([0-9]\{1,\}\).*/\2/p' | head -n 1
}

# --- checks ------------------------------------------------------------------

check_toolchain() {
    section 'python toolchain'
    ok "virtualenv ${VENV_BIN%/bin}"

    if [[ -x "${VENV_BIN}/python" ]]; then
        ok '  python'
    else
        fail '  python is missing from the virtualenv'
    fi

    # pio deliberately lives OUTSIDE this virtualenv. PlatformIO Core installs
    # itself into ~/.platformio/penv so that every embedded project on the
    # machine shares one copy, and it is reached through a symlink in
    # ~/.local/bin. So require it on PATH, not in the venv.
    local tool
    if tool="$(command -v pio)"; then
        ok "  pio -> ${tool}"
    else
        fail '  pio is not on PATH (run scripts/install-toolchain.sh)'
    fi

    if tool="$(esptool_name)"; then
        ok "  ${tool} (major version $(esptool_major))"
    else
        fail '  esptool is missing from the virtualenv'
    fi

    local line
    while IFS= read -r line; do
        [[ -n ${line} ]] && info "  ${line}"
    done < <(python --version 2>&1; pio --version 2>&1)
}

# Confirms this account can actually open each attached board.
check_access() {
    local dev
    for dev in "${ATTACHED_PORTS[@]}"; do
        section "board on ${dev}"
        if [[ -r ${dev} && -w ${dev} ]]; then
            ok '  readable and writable by this account'
        else
            fail "  not accessible; run \"${SCRIPTS_DIR}/heltec-setup.sh check\" as root"
        fi
        check_port_free "${dev}"
    done
}

# --- subcommands -------------------------------------------------------------

cmd_check() {
    printf 'project : %s\n' "${PROJECT_DIR}"
    printf 'account : %s\n' "$(id -un)"

    check_kernel_driver
    check_toolchain
    check_usb
    check_access

    report_result
}

cmd_ports() {
    local -a ports=()
    mapfile -t ports < <(list_ports)
    [[ ${#ports[@]} -gt 0 ]] || die "no Heltec board attached (expected USB ${USB_VID}:${USB_PID})"
    local dev
    for dev in "${ports[@]}"; do
        printf '%s\t%s\n' "${dev}" "$(port_by_path "${dev}")"
    done
}

cmd_build() {
    section 'build'
    pio run
}

cmd_clean() {
    section 'clean'
    pio run -t clean
}

cmd_upload() {
    local port
    port="$(resolve_port "${1:-}")"
    section "upload to ${port}"
    pio run -t upload --upload-port "${port}"
}

cmd_monitor() {
    local port
    port="$(resolve_port "${1:-}")"
    section "monitor ${port} at ${SERIAL_BAUD} (ctrl-c ctrl-c to exit)"
    pio device monitor --port "${port}"
}

# Flash, then immediately watch the board boot. This is the usual edit-run loop.
cmd_flash() {
    local port
    port="$(resolve_port "${1:-}")"
    section "upload to ${port}"
    pio run -t upload --upload-port "${port}"
    section "monitor ${port} at ${SERIAL_BAUD} (ctrl-c ctrl-c to exit)"
    pio device monitor --port "${port}"
}

cmd_chip_id() {
    local port tool sub
    port="$(resolve_port "${1:-}")"
    tool="$(esptool_name)" || die "esptool is not installed in ${VENV_BIN}"
    # esptool 5 hyphenated its subcommands and warns on the underscore spelling;
    # esptool 4 understands only the underscore form.
    if [[ "$(esptool_major)" -ge 5 ]]; then
        sub='chip-id'
    else
        sub='chip_id'
    fi

    section "chip id on ${port}"
    info 'if this fails to sync: hold PRG, tap RST, release PRG, run again'
    "${tool}" --chip esp32s3 --port "${port}" "${sub}"
}

cmd_raw() {
    local port
    port="$(resolve_port "${1:-}")"
    section "raw read of ${port} at ${SERIAL_BAUD} (ctrl-c to exit)"
    info 'press RST on the board to see its banner'
    stty -F "${port}" "${SERIAL_BAUD}" raw -echo -echoe -echok -crtscts
    cat "${port}"
}

usage() {
    cat <<USAGE
Usage: $(basename -- "$0") [subcommand] [port]

Developer actions. Run as $(id -un), never as root. Host setup that does need
root lives in ${SCRIPTS_DIR}/heltec-setup.sh.

  check           toolchain and device readiness; non-zero if anything is wrong
  ports           list attached boards with their stable by-path names
  build           pio run
  clean           pio run -t clean
  upload [port]   build if needed, then write the firmware and reset the board
  monitor [port]  pio device monitor at ${SERIAL_BAUD} baud
  flash [port]    upload, then monitor -- the usual edit-run loop
  chip-id [port]  identify the attached ESP32-S3 with esptool
  raw [port]      read the serial port with stty and cat, no PlatformIO

Port defaults to the single attached USB ${USB_VID}:${USB_PID} device, and is
required when more than one board is plugged in.
USAGE
}

main() {
    local subcommand="${1:-check}"
    shift || true

    case "${subcommand}" in
        check)              cmd_check ;;
        ports)              cmd_ports ;;
        build)              cmd_build ;;
        clean)              cmd_clean ;;
        upload)             cmd_upload "${1:-}" ;;
        monitor)            cmd_monitor "${1:-}" ;;
        flash)              cmd_flash "${1:-}" ;;
        chip-id)            cmd_chip_id "${1:-}" ;;
        raw)                cmd_raw "${1:-}" ;;
        -h | --help | help) usage ;;
        *)
            printf 'unknown subcommand: %s\n\n' "${subcommand}" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
