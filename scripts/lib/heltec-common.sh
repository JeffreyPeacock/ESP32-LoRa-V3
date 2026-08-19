# shellcheck shell=bash
#
# Shared definitions for heltec-setup.sh (root) and heltec-dev.sh (developer).
#
# Sourced, never executed. The caller is responsible for `set -euo pipefail`.
# Several constants below are read only by the sourcing scripts, so each carries
# a SC2034 waiver -- shellcheck cannot see across the source boundary.

[[ -n ${_HELTEC_COMMON_LOADED:-} ]] && return 0
_HELTEC_COMMON_LOADED=1

# --- paths -------------------------------------------------------------------

_HELTEC_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname -- "${_HELTEC_LIB_DIR}")"
readonly SCRIPTS_DIR
PROJECT_DIR="$(dirname -- "${SCRIPTS_DIR}")"
readonly PROJECT_DIR

# The account that owns the checkout is the one that builds and flashes.
# Override with HELTEC_USER if that inference is wrong.
if [[ -n ${HELTEC_USER:-} ]]; then
    DEV_USER="${HELTEC_USER}"
else
    DEV_USER="$(stat -c '%U' "${PROJECT_DIR}")"
fi
# shellcheck disable=SC2034  # consumed by the sourcing script
readonly DEV_USER

# --- board constants ---------------------------------------------------------

readonly RULE_NAME='99-heltec-cp210x.rules'
# shellcheck disable=SC2034  # consumed by the sourcing script
readonly RULE_DEST="/etc/udev/rules.d/${RULE_NAME}"

# Silicon Labs CP2102N. This is the USB-UART bridge the V3's USB-C port is
# wired to; the ESP32-S3's own USB peripheral (303a:1001) is not connected.
readonly USB_VID='10c4'
readonly USB_PID='ea60'

# shellcheck disable=SC2034  # consumed by the sourcing script
readonly SERIAL_BAUD='115200'

# --- output ------------------------------------------------------------------

FAILURES=0

ok()      { printf '  [ ok ] %s\n' "$*"; }
info()    { printf '  [ -- ] %s\n' "$*"; }
warn()    { printf '  [warn] %s\n' "$*" >&2; }
fail()    { printf '  [FAIL] %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

# Prints the pass/fail tail of a check run and returns the right exit status.
report_result() {
    section 'result'
    if [[ ${FAILURES} -eq 0 ]]; then
        ok 'all checks passed'
        return 0
    fi
    fail "${FAILURES} check(s) failed"
    return 1
}

# --- device helpers ----------------------------------------------------------

# Prints the property value for a device, or nothing.
dev_property() {
    local dev="$1" key="$2"
    udevadm info --name="${dev}" --query=property 2>/dev/null |
        sed -n "s/^${key}=//p"
}

# Prints every tty that is a Heltec board, one per line.
list_ports() {
    local dev
    for dev in /dev/ttyUSB*; do
        [[ -e ${dev} ]] || continue
        [[ "$(dev_property "${dev}" ID_VENDOR_ID)" == "${USB_VID}" ]] || continue
        [[ "$(dev_property "${dev}" ID_MODEL_ID)" == "${USB_PID}" ]] || continue
        printf '%s\n' "${dev}"
    done
}

# Prints the by-path name for a device, which is the only stable way to tell
# two Heltec boards apart. Falls back to the tty name.
port_by_path() {
    local dev="$1" path
    path="$(dev_property "${dev}" ID_PATH)"
    if [[ -n ${path} && -e "/dev/serial/by-path/${path}-port0" ]]; then
        printf '/dev/serial/by-path/%s-port0\n' "${path}"
    else
        printf '%s\n' "${dev}"
    fi
}

# Resolves the port to use: explicit argument wins, otherwise autodetect.
# Refuses to guess when several boards are attached.
resolve_port() {
    local requested="${1:-}"
    if [[ -n ${requested} ]]; then
        [[ -e ${requested} ]] || die "no such device: ${requested}"
        printf '%s\n' "${requested}"
        return 0
    fi

    local -a ports=()
    mapfile -t ports < <(list_ports)

    case ${#ports[@]} in
        0)
            die "no Heltec board found (expected USB ${USB_VID}:${USB_PID}); pass the port explicitly"
            ;;
        1)
            printf '%s\n' "${ports[0]}"
            ;;
        *)
            {
                printf 'error: %d Heltec boards attached; name one explicitly:\n' "${#ports[@]}"
                local dev
                for dev in "${ports[@]}"; do
                    printf '  %s  ->  %s\n' "${dev}" "$(port_by_path "${dev}")"
                done
            } >&2
            exit 1
            ;;
    esac
}

# --- shared checks -----------------------------------------------------------

check_kernel_driver() {
    section 'kernel driver'
    if modinfo cp210x >/dev/null 2>&1; then
        ok 'cp210x module available'
    else
        fail 'cp210x module not found in this kernel'
    fi
    # Not `lsmod | grep -q`: under `set -o pipefail`, grep -q exits on the first
    # match, lsmod dies of SIGPIPE, and the pipeline reports 141 even though the
    # match succeeded. Every check in these scripts avoids grep -q behind a pipe.
    local modules
    modules="$(lsmod)"
    if grep -q '^cp210x' <<<"${modules}"; then
        ok 'cp210x loaded'
    else
        info 'cp210x not loaded (it autoloads on plug-in)'
    fi
}

# Reports how many boards are attached and prints each one, or records a
# failure if none are. Sets ATTACHED_PORTS as a side effect.
ATTACHED_PORTS=()
check_usb() {
    section 'USB enumeration'
    ATTACHED_PORTS=()

    local lsusb_out
    lsusb_out="$(lsusb -d "${USB_VID}:${USB_PID}" 2>/dev/null || true)"
    if [[ -z ${lsusb_out} ]]; then
        fail "no USB device ${USB_VID}:${USB_PID} -- board not plugged in, or the cable is charge-only"
        return 0
    fi

    mapfile -t ATTACHED_PORTS < <(list_ports)
    if [[ ${#ATTACHED_PORTS[@]} -eq 0 ]]; then
        fail 'USB device present but no ttyUSB claimed it; see the "dmesg" subcommand'
        return 0
    fi

    ok "${#ATTACHED_PORTS[@]} board(s) attached"
    local dev
    for dev in "${ATTACHED_PORTS[@]}"; do
        info "${dev} -> $(port_by_path "${dev}")"
    done

    if [[ ${#ATTACHED_PORTS[@]} -gt 1 ]]; then
        info 'these boards share the factory serial 0001, so /dev/heltec-0001'
        info 'resolves to only one of them; use the by-path names above'
    fi
}

# Reports anything already holding the port, which is the usual reason an
# upload cannot open it.
check_port_free() {
    local dev="$1" holders=''
    if command -v fuser >/dev/null 2>&1; then
        holders="$(fuser "${dev}" 2>/dev/null || true)"
    elif command -v lsof >/dev/null 2>&1; then
        holders="$(lsof -t "${dev}" 2>/dev/null || true)"
    else
        info '  cannot tell whether the port is free (no fuser, no lsof)'
        return 0
    fi

    if [[ -z ${holders//[[:space:]]/} ]]; then
        ok '  port is free'
    else
        fail "  port held by PID(s):${holders}"
        # shellcheck disable=SC2086  # deliberate word splitting of the PID list
        ps -o pid=,user=,comm= -p ${holders} 2>/dev/null || true
    fi
}

# --- python interpreter ------------------------------------------------------

# Prints the bin directory of the virtualenv holding the Meshtastic CLI and
# esptool. Takes an optional tool name that the candidate must also contain.
#
# This project is developed against a pyenv virtualenv, but nothing here
# depends on pyenv. Four layouts are accepted, in order, so a contributor who
# does not use pyenv is not forced to install it:
#
#   1. ${HELTEC_VENV}          -- explicit override, wins over everything
#   2. ${PROJECT_DIR}/.venv    -- a plain `python3 -m venv .venv` in the checkout
#   3. ${VIRTUAL_ENV}          -- a venv the caller has already activated
#   4. pyenv                   -- nearest .python-version, then ${PYENV_ROOT}/version
#
# A .venv inside the checkout outranks ${VIRTUAL_ENV} because it names *this*
# project, whereas an activated environment may be anything the caller happened
# to be in. Activating the .venv gives the same answer either way. A candidate
# that lacks python, or lacks the requested tool, is skipped rather than fatal,
# so a half-built .venv falls through instead of blocking the working one.
#
# The pyenv branch is resolved directly rather than through the shims. An IDE,
# a cron job or `su -c` starts a *non-interactive* shell, and Ubuntu's
# ~/.bashrc returns on its first line for those, so `eval "$(pyenv init -)"`
# never runs and the shims do not exist.
resolve_venv_bin() {
    local want="${1:-}" bin root name='' dir
    local -a candidates=()

    [[ -n ${HELTEC_VENV:-} ]] && candidates+=("${HELTEC_VENV%/}/bin")
    candidates+=("${PROJECT_DIR}/.venv/bin")
    [[ -n ${VIRTUAL_ENV:-} ]] && candidates+=("${VIRTUAL_ENV%/}/bin")

    root="${PYENV_ROOT:-${HOME}/.pyenv}"
    if [[ -d ${root} ]]; then
        dir="${PROJECT_DIR}"
        while [[ ${dir} != '/' ]]; do
            if [[ -f "${dir}/.python-version" ]]; then
                name="$(head -n 1 -- "${dir}/.python-version")"
                break
            fi
            dir="$(dirname -- "${dir}")"
        done
        if [[ -z ${name} && -f "${root}/version" ]]; then
            name="$(head -n 1 -- "${root}/version")"
        fi
        name="${name//[[:space:]]/}"
        # pyenv-virtualenv leaves versions/<name> as a symlink into
        # versions/<python>/envs/<name>, so this one path covers both layouts.
        [[ -n ${name} ]] && candidates+=("${root}/versions/${name}/bin")
    fi

    for bin in "${candidates[@]}"; do
        [[ -x "${bin}/python" ]] || continue
        [[ -z ${want} || -x "${bin}/${want}" ]] || continue
        printf '%s\n' "${bin}"
        return 0
    done
    return 1
}

# The message every caller should print when resolve_venv_bin fails. Kept here
# so the four search locations are described in exactly one place.
venv_hint() {
    cat <<HINT
no virtualenv found with the Meshtastic CLI and esptool. Looked at:
  \${HELTEC_VENV}/bin              ${HELTEC_VENV:-(unset)}
  ${PROJECT_DIR}/.venv/bin
  \${VIRTUAL_ENV}/bin              ${VIRTUAL_ENV:-(unset)}
  pyenv, via the nearest .python-version or ${PYENV_ROOT:-${HOME}/.pyenv}/version

Either run ./scripts/install-toolchain.sh (sets up pyenv, what this project
uses), or make a plain one and point at it:
  python3 -m venv "${PROJECT_DIR}/.venv"
  "${PROJECT_DIR}/.venv/bin/pip" install meshtastic esptool
See "Python environment" in README.md.
HINT
}
