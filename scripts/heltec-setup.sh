#!/usr/bin/env bash
#
# One-time host setup for the Heltec WiFi LoRa 32 (V3).
#
# Run it from a normal shell: the few commands that need root escalate through
# sudo themselves, and running the script as root works too. This touches only
# system state -- the udev rule that keeps ModemManager off the board's tty,
# group membership, ModemManager itself. It never builds, flashes or opens a
# serial port; that is heltec-dev.sh, which must NOT be root.
#
# Idempotent: re-running changes nothing already in the desired state, and the
# udev rule is rewritten (and udev reloaded) only when its content differs.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/heltec-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/heltec-common.sh"

# --- privilege escalation ----------------------------------------------------
#
# Escalate per command rather than re-executing the whole script under sudo, so
# that `check` -- which reads nothing privileged, since the rule file is 0644 --
# never prompts for a password. Expands to nothing when already root.
if [[ ${EUID} -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 ||
        die 'not running as root, and sudo is not installed'
    SUDO=(sudo)
fi
readonly SUDO

# Takes the password prompt up front instead of partway through the output, and
# refreshes the sudo timestamp so a slow run cannot be interrupted by a second
# prompt between commands.
need_privileges() {
    [[ ${EUID} -eq 0 ]] && return 0
    sudo -v || die 'could not obtain root privileges'
}

# Emits the udev rule on stdout. Single source of truth -- `install` compares
# this against the installed file rather than copying unconditionally.
emit_rule() {
    cat <<'RULE'
# Heltec WiFi LoRa 32 V3 -- CP2102N USB-UART bridge (Silicon Labs 10c4:ea60).
#
# Managed by scripts/heltec-setup.sh. Edit the script, not this file.
#
# ModemManager probes every new tty by writing AT commands to it. On this board
# the tty is the ESP32-S3's bootloader UART, so the probe collides with esptool
# for the first several seconds after plug-in and the upload fails with
# "Failed to connect to ESP32-S3". Tag the device so ModemManager skips it.
#
# The symlink gives a name that survives ttyUSB renumbering. It does NOT
# distinguish one board from another: Heltec ships these CP2102Ns with the
# factory-default serial 0001, so every board produces /dev/heltec-0001 and
# udev arbitrates between them. With more than one board attached, address them
# by physical USB port via /dev/serial/by-path/ instead.

SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", \
  ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1", \
  MODE="0660", GROUP="dialout", \
  SYMLINK+="heltec-$attr{serial}"
RULE
}

reload_udev() {
    "${SUDO[@]}" udevadm control --reload-rules
    "${SUDO[@]}" udevadm trigger --subsystem-match=tty --action=add
}

# --- subcommands -------------------------------------------------------------

cmd_install() {
    need_privileges

    section 'udev rule'
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064  # expand tmp now, not at trap time
    trap "rm -f -- '${tmp}'" RETURN
    emit_rule >"${tmp}"

    if [[ -f ${RULE_DEST} ]] && cmp -s "${tmp}" "${RULE_DEST}"; then
        ok "${RULE_DEST} already current"
        return 0
    fi

    if [[ -f ${RULE_DEST} ]]; then
        info "${RULE_DEST} differs, rewriting"
    else
        info "installing ${RULE_DEST}"
    fi
    "${SUDO[@]}" install -m 0644 -o root -g root "${tmp}" "${RULE_DEST}"
    reload_udev
    ok 'rule installed, udev reloaded'
    info 'unplug and replug the board for the rule to apply to it'
}

cmd_uninstall() {
    need_privileges

    section 'udev rule'
    if [[ ! -e ${RULE_DEST} ]]; then
        ok "${RULE_DEST} already absent"
        return 0
    fi
    "${SUDO[@]}" rm -f -- "${RULE_DEST}"
    reload_udev
    ok "removed ${RULE_DEST}"
}

cmd_add_dialout() {
    need_privileges
    local who="${1:-${DEV_USER}}"

    section "group membership for ${who}"
    getent passwd "${who}" >/dev/null || die "user '${who}' does not exist"

    local groups
    groups=" $(id -nG "${who}") "
    if [[ ${groups} == *' dialout '* ]]; then
        ok "${who} is already in group dialout"
        return 0
    fi
    "${SUDO[@]}" usermod -aG dialout "${who}"
    ok "added ${who} to group dialout"
    info 'the new group only applies to sessions started after this point;'
    info "${who} must log out and back in"
}

cmd_disable_modemmanager() {
    need_privileges

    section 'ModemManager'
    if ! systemctl list-unit-files ModemManager.service >/dev/null 2>&1; then
        ok 'not installed, nothing to do'
        return 0
    fi
    if ! systemctl is-enabled --quiet ModemManager 2>/dev/null &&
        ! systemctl is-active --quiet ModemManager; then
        ok 'already disabled and stopped'
        return 0
    fi
    warn 'only do this if this machine has no cellular modem'
    "${SUDO[@]}" systemctl disable --now ModemManager
    ok 'disabled and stopped'
}

cmd_dmesg() {
    section 'recent kernel messages'
    local out
    out="$(dmesg -T 2>/dev/null || true)"
    if [[ -z ${out} ]]; then
        # kernel.dmesg_restrict is 1 on Ubuntu, so an unprivileged read returns
        # nothing at all. Escalate only then -- on a host that leaves the kernel
        # log open this subcommand never prompts.
        need_privileges
        out="$("${SUDO[@]}" dmesg -T 2>/dev/null || true)"
    fi
    [[ -n ${out} ]] || die 'cannot read the kernel log'
    local matched
    matched="$(grep -iE 'cp210x|ttyUSB' <<<"${out}" | tail -n 20 || true)"
    if [[ -n ${matched} ]]; then
        printf '%s\n' "${matched}"
    else
        info 'nothing matched cp210x or ttyUSB'
    fi
}

check_rule_installed() {
    section 'udev rule'
    if [[ ! -f ${RULE_DEST} ]]; then
        fail "${RULE_DEST} is not installed; run \"$(basename -- "$0") install\""
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f -- '${tmp}'" RETURN
    emit_rule >"${tmp}"
    if cmp -s "${tmp}" "${RULE_DEST}"; then
        ok "${RULE_DEST} matches this script"
    else
        fail "${RULE_DEST} differs from this script; run \"$(basename -- "$0") install\""
    fi
}

check_dialout() {
    section 'developer account'
    if ! getent passwd "${DEV_USER}" >/dev/null; then
        fail "user '${DEV_USER}' does not exist (set HELTEC_USER)"
        return 0
    fi
    # Padded substring match rather than `id -nG | tr | grep -qx`, which is the
    # SIGPIPE-under-pipefail trap described in the library and fails at random
    # depending on where dialout lands in the group list.
    local groups
    groups=" $(id -nG "${DEV_USER}") "
    if [[ ${groups} == *' dialout '* ]]; then
        ok "${DEV_USER} is in group dialout"
    else
        fail "${DEV_USER} is not in group dialout; run \"$(basename -- "$0") add-dialout\""
    fi
}

check_modemmanager() {
    section 'ModemManager'
    if ! systemctl list-unit-files ModemManager.service >/dev/null 2>&1; then
        ok 'not installed'
    elif systemctl is-active --quiet ModemManager; then
        info 'running -- it probes new ttys, so each board must carry the ignore tag'
    else
        ok 'installed but not running'
    fi
}

# Confirms the rule actually took effect on each attached board.
check_tagging() {
    local dev
    for dev in "${ATTACHED_PORTS[@]}"; do
        section "board on ${dev}"

        local links
        links="$(dev_property "${dev}" DEVLINKS)"
        if [[ ${links} == *'/dev/heltec-'* ]]; then
            ok '  has a /dev/heltec-* symlink'
        else
            fail '  no /dev/heltec-* symlink; run "install", then unplug and replug'
        fi

        local group mode
        group="$(stat -c '%G' "${dev}")"
        mode="$(stat -c '%a' "${dev}")"
        if [[ ${group} == 'dialout' && ${mode} == '660' ]]; then
            ok "  permissions ${mode} root:${group}"
        else
            fail "  permissions are ${mode} group ${group}; expected 660 dialout"
        fi

        if [[ "$(dev_property "${dev}" ID_MM_DEVICE_IGNORE)" == '1' ]]; then
            ok '  ID_MM_DEVICE_IGNORE=1, ModemManager will not probe it'
        elif systemctl is-active --quiet ModemManager 2>/dev/null; then
            fail '  not tagged against ModemManager; run "install", then replug'
        else
            info '  not tagged, but ModemManager is not running'
        fi
    done
}

cmd_check() {
    printf 'project : %s\n' "${PROJECT_DIR}"
    printf 'account : %s\n' "${DEV_USER}"

    check_kernel_driver
    check_rule_installed
    check_dialout
    check_modemmanager
    check_usb
    check_tagging

    report_result
}

usage() {
    cat <<USAGE
Usage: $(basename -- "$0") [subcommand]

Host setup. Run it from a normal shell -- the commands that need root escalate
through sudo and will prompt for a password once; running the whole script as
root also works. Nothing here builds or flashes; use heltec-dev.sh as
${DEV_USER} for that.

Default subcommand is 'setup'.

  setup                 install the udev rule, then run all checks   [sudo]
  install               install or refresh the udev rule             [sudo]
  uninstall             remove the udev rule                         [sudo]
  check                 verify the host is ready; non-zero if anything is wrong
  add-dialout [user]    add a user to the dialout group (default ${DEV_USER})  [sudo]
  disable-modemmanager  stop and disable ModemManager (no cellular modem only) [sudo]
  dmesg                 recent cp210x / ttyUSB kernel messages   [sudo if restricted]

'check' reads nothing privileged and never prompts.
USAGE
}

main() {
    local subcommand="${1:-setup}"
    shift || true

    case "${subcommand}" in
        setup)
            cmd_install
            cmd_check
            ;;
        install)              cmd_install ;;
        uninstall)            cmd_uninstall ;;
        check)                cmd_check ;;
        add-dialout)          cmd_add_dialout "${1:-}" ;;
        disable-modemmanager) cmd_disable_modemmanager ;;
        dmesg)                cmd_dmesg ;;
        -h | --help | help)   usage ;;
        *)
            printf 'unknown subcommand: %s\n\n' "${subcommand}" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
