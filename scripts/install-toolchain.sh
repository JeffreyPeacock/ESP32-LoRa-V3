#!/usr/bin/env bash
#
# Bootstrap the host toolchain for Heltec WiFi LoRa 32 V3 work.
#
#   1. PlatformIO Core into ~/.platformio/penv   (project-neutral, no venv of its own)
#   2. Symlinks so `pio` is on PATH everywhere
#   3. A pyenv virtualenv holding the Meshtastic CLI and esptool
#
# Run as a normal user. Nothing here needs root; the one part that does --
# the udev rule that keeps ModemManager off the board's serial port -- lives in
# heltec-setup.sh and is called out at the end.
#
# Idempotent: re-running skips whatever is already in place.
#
# Deliberately self-contained -- it does not source scripts/lib/heltec-common.sh,
# because it has to run on a machine that may have nothing but this one file.

set -euo pipefail

# --- defaults ----------------------------------------------------------------

PYTHON_VERSION='3.12.12'
VENV_NAME='meshtastic'

# PlatformIO Core builds its own private virtualenv (penv) from whichever
# interpreter runs the installer. Empty means "the pyenv Python named by
# PYTHON_VERSION", resolved during preflight. That interpreter always ships a
# working venv module, whereas a distro /usr/bin/python3 commonly needs a
# separate python3-venv package installed first. Override with --penv-python.
PENV_PYTHON=''

PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-${HOME}/.platformio}"
LOCAL_BIN="${HOME}/.local/bin"
INSTALLER_URL='https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py'

PROJECT_DIR=''
SKIP_PLATFORMIO=0
REINSTALL_PLATFORMIO=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# If this script is sitting in a project's scripts/ directory, adopt that project
# as the one to pin the virtualenv to. A standalone copy pins nothing.
if [[ -f "${SCRIPT_DIR}/../platformio.ini" ]]; then
    PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
fi

# --- output ------------------------------------------------------------------

ok()      { printf '  [ ok ] %s\n' "$*"; }
info()    { printf '  [ -- ] %s\n' "$*"; }
warn()    { printf '  [warn] %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- arguments ---------------------------------------------------------------

usage() {
    cat <<USAGE
Usage: $(basename -- "$0") [options]

Installs PlatformIO Core, then a pyenv virtualenv with the Meshtastic CLI and
esptool. Run as a normal user, not root.

  --python-version X     pyenv Python for the virtualenv (default ${PYTHON_VERSION})
  --venv-name NAME       name of the pyenv virtualenv (default ${VENV_NAME})
  --penv-python PATH     interpreter PlatformIO builds its penv from
                         (default: the pyenv \${PYTHON_VERSION} interpreter)
  --project-dir DIR      run 'pyenv local NAME' here (default: autodetected)
  --no-project-pin       do not run 'pyenv local' anywhere
  --skip-platformio      only do the virtualenv; use this if you just need to
                         configure a radio and never compile firmware
  --reinstall-platformio rebuild ~/.platformio/penv even if it already works
  -h, --help             this message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --python-version)      PYTHON_VERSION="${2:?}"; shift 2 ;;
        --venv-name)           VENV_NAME="${2:?}"; shift 2 ;;
        --penv-python)         PENV_PYTHON="${2:?}"; shift 2 ;;
        --project-dir)         PROJECT_DIR="${2:?}"; shift 2 ;;
        --no-project-pin)      PROJECT_DIR=''; shift ;;
        --skip-platformio)     SKIP_PLATFORMIO=1; shift ;;
        --reinstall-platformio) REINSTALL_PLATFORMIO=1; shift ;;
        -h | --help)           usage; exit 0 ;;
        *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

# --- preflight ---------------------------------------------------------------

preflight() {
    section 'preflight'

    [[ ${EUID} -ne 0 ]] ||
        die 'do not run this as root -- it installs into your home directory'

    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=(curl)
    command -v pyenv >/dev/null 2>&1 || missing+=(pyenv)
    [[ ${#missing[@]} -eq 0 ]] ||
        die "missing required command(s): ${missing[*]}"
    ok "pyenv $(pyenv --version 2>&1 | awk '{print $2}')"

    # `pyenv virtualenv` is a separate plugin and is easy to be missing.
    local cmds
    cmds="$(pyenv commands)"
    grep -qx 'virtualenv' <<<"${cmds}" ||
        die 'the pyenv-virtualenv plugin is not installed
       see https://github.com/pyenv/pyenv-virtualenv#installation'
    ok 'pyenv-virtualenv plugin present'

    # The interpreter backing both the virtualenv and, by default, PlatformIO's
    # penv. Built here rather than alongside the virtualenv because PlatformIO
    # is installed first and may need it.
    #
    # Not `pyenv versions --bare | grep -qx`: under `set -o pipefail`, grep -q
    # exits at the first match, pyenv dies of SIGPIPE, and the pipeline reports
    # 141 despite the match succeeding.
    local versions
    versions="$(pyenv versions --bare)"
    if ! grep -qx "${PYTHON_VERSION}" <<<"${versions}"; then
        info "Python ${PYTHON_VERSION} not present, building it (several minutes)"
        info 'if this fails, install the build dependencies first:'
        info '  https://github.com/pyenv/pyenv/wiki#suggested-build-environment'
        pyenv install -s "${PYTHON_VERSION}"
    fi
    ok "Python ${PYTHON_VERSION} available"

    if [[ -z ${PENV_PYTHON} ]]; then
        PENV_PYTHON="$(pyenv prefix "${PYTHON_VERSION}")/bin/python3"
    fi

    if [[ ${SKIP_PLATFORMIO} -eq 0 ]]; then
        [[ -x ${PENV_PYTHON} ]] ||
            die "no interpreter at ${PENV_PYTHON} (override with --penv-python)"
        ok "penv interpreter ${PENV_PYTHON} ($("${PENV_PYTHON}" --version 2>&1))"
        "${PENV_PYTHON}" -c 'import venv' 2>/dev/null ||
            die "${PENV_PYTHON} cannot create virtualenvs; install its venv module
       (Debian/Ubuntu: sudo apt install python3-venv)"
    fi
}

# --- 1. PlatformIO Core ------------------------------------------------------

install_platformio() {
    section 'PlatformIO Core'

    if [[ ${SKIP_PLATFORMIO} -eq 1 ]]; then
        info 'skipped by request'
        return 0
    fi

    local pio_bin="${PLATFORMIO_CORE_DIR}/penv/bin/pio"
    if [[ ${REINSTALL_PLATFORMIO} -eq 1 ]]; then
        info 'rebuilding penv by request'
        rm -rf -- "${PLATFORMIO_CORE_DIR}/penv"
    elif [[ -x ${pio_bin} ]] && "${pio_bin}" --version >/dev/null 2>&1; then
        ok "already installed: $("${pio_bin}" --version)"
        info "rebuild with --reinstall-platformio"
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand tmp now, not at trap time
    trap "rm -rf -- '${tmp}'" RETURN

    info "fetching ${INSTALLER_URL}"
    curl -fsSL -o "${tmp}/get-platformio.py" "${INSTALLER_URL}" ||
        die 'could not download the PlatformIO installer'

    # The interpreter that runs the installer is the one penv is built from,
    # which is why this is an absolute path and not the bare word python3 --
    # that would hit a pyenv shim and couple PlatformIO to pyenv.
    info "installing with ${PENV_PYTHON}"
    "${PENV_PYTHON}" "${tmp}/get-platformio.py" ||
        die 'the PlatformIO installer failed'

    [[ -x ${pio_bin} ]] || die "installer finished but ${pio_bin} is missing"
    ok "$("${pio_bin}" --version)"
}

# --- 2. symlinks -------------------------------------------------------------

link_platformio() {
    section 'PATH symlinks'

    if [[ ${SKIP_PLATFORMIO} -eq 1 ]]; then
        info 'skipped by request'
        return 0
    fi

    mkdir -p -- "${LOCAL_BIN}"

    # Symlink the three entry points rather than putting penv/bin on PATH:
    # that directory also holds python, pip and pyserial-miniterm, which would
    # shadow the pyenv shims.
    local tool
    for tool in pio platformio piodebuggdb; do
        local src="${PLATFORMIO_CORE_DIR}/penv/bin/${tool}"
        if [[ ! -x ${src} ]]; then
            warn "${tool} not found in penv, skipping"
            continue
        fi
        ln -sfn -- "${src}" "${LOCAL_BIN}/${tool}"
        ok "${LOCAL_BIN}/${tool} -> ${src}"
    done

    case ":${PATH}:" in
        *":${LOCAL_BIN}:"*)
            ok "${LOCAL_BIN} is on PATH"
            ;;
        *)
            warn "${LOCAL_BIN} is NOT on PATH"
            warn "add this to your shell rc, then open a new shell:"
            warn "    export PATH=\"\${HOME}/.local/bin:\${PATH}\""
            ;;
    esac
}

# --- 3. meshtastic virtualenv ------------------------------------------------

create_venv() {
    section "pyenv virtualenv '${VENV_NAME}'"

    local versions
    versions="$(pyenv versions --bare)"

    if grep -qx "${VENV_NAME}" <<<"${versions}"; then
        ok "'${VENV_NAME}' already exists"
        return 0
    fi

    pyenv virtualenv "${PYTHON_VERSION}" "${VENV_NAME}"
    ok "created '${VENV_NAME}'"
}

prep_venv() {
    section "packages in '${VENV_NAME}'"

    local bin="${PYENV_ROOT:-${HOME}/.pyenv}/versions/${VENV_NAME}/bin"
    [[ -x "${bin}/pip" ]] || die "no pip at ${bin}/pip"

    "${bin}/pip" install --quiet --upgrade pip
    ok "pip $("${bin}/pip" --version | awk '{print $2}')"

    # esptool belongs here rather than earlier: it lives inside this virtualenv,
    # so it cannot be installed before the virtualenv exists. It is what flashes
    # Meshtastic release images; PlatformIO carries its own copy separately for
    # firmware we compile ourselves.
    "${bin}/pip" install --quiet --upgrade meshtastic esptool
    ok "meshtastic $("${bin}/meshtastic" --version 2>&1)"
    ok "esptool $("${bin}/esptool" version 2>/dev/null | tail -1)"

    pyenv rehash
    ok 'pyenv rehash'
}

pin_project() {
    section 'project pin'

    if [[ -z ${PROJECT_DIR} ]]; then
        info 'no project directory; skipping (use --project-dir to set one)'
        return 0
    fi
    [[ -d ${PROJECT_DIR} ]] || die "no such directory: ${PROJECT_DIR}"

    local pin="${PROJECT_DIR}/.python-version"
    if [[ -f ${pin} ]] && [[ "$(head -n 1 -- "${pin}")" == "${VENV_NAME}" ]]; then
        ok "${pin} already pins ${VENV_NAME}"
        return 0
    fi

    ( cd -- "${PROJECT_DIR}" && pyenv local "${VENV_NAME}" )
    ok "${pin} -> ${VENV_NAME}"
}

# --- verify ------------------------------------------------------------------

verify() {
    section 'verify'

    local bin="${PYENV_ROOT:-${HOME}/.pyenv}/versions/${VENV_NAME}/bin"
    local failed=0

    if [[ ${SKIP_PLATFORMIO} -eq 0 ]]; then
        if command -v pio >/dev/null 2>&1; then
            ok "pio -> $(readlink -f "$(command -v pio)")"
        else
            warn 'pio is not on PATH (see the symlink warning above)'
            failed=1
        fi
    fi

    local tool
    for tool in meshtastic esptool; do
        if [[ -x "${bin}/${tool}" ]]; then
            ok "${tool} -> ${bin}/${tool}"
        else
            warn "${tool} missing from the virtualenv"
            failed=1
        fi
    done

    section 'next steps'
    if [[ -n ${PROJECT_DIR} ]]; then
        info "cd ${PROJECT_DIR}"
    fi
    info 'the serial port needs a udev rule so ModemManager does not fight'
    info 'esptool for the board. That part needs root:'
    info "    ${SCRIPT_DIR}/heltec-setup.sh setup"
    printf '\n'

    return "${failed}"
}

main() {
    preflight
    install_platformio
    link_platformio
    create_venv
    prep_venv
    pin_project
    verify
}

main
