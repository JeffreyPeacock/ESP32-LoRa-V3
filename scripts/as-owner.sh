#!/usr/bin/env bash
#
# Run a command with the GitHub CLI authenticated as the account that owns this
# repository and its project board.
#
#   ./scripts/as-owner.sh gh issue close 18 --repo JeffreyPeacock/ESP32-LoRa-V3
#   ./scripts/as-owner.sh gh project item-list 10 --owner JeffreyPeacock
#
# Two accounts are logged into gh on this machine because the owner works on
# several projects at once. Everything touching THIS repo, its board, and any
# cross-component ticket filed on its behalf must go out as JeffreyPeacock.
# WhiteFeatherAI has pull access only here, and the failure is misleading: an
# issue can still be created, but closing it fails with a message about
# permissions rather than about the wrong account being selected.
#
# gh has no per-repository account setting and no --user flag on its commands,
# so the active account is global and this script switches it, runs the command,
# and switches back. git needs none of this: user.name and user.email are pinned
# in this repository's own config, which overrides the global file and cannot
# leak into another project.
#
# Exit status is the command's own, so this is safe to use in a pipeline.

set -uo pipefail

TARGET_ACCOUNT='JeffreyPeacock'
LOCK_FILE="${TMPDIR:-/tmp}/gh-active-account.lock"

die() { printf 'as-owner: %s\n' "$*" >&2; exit 1; }

[ "$#" -gt 0 ] || die "usage: $(basename -- "$0") <command> [args...]"

command -v gh >/dev/null || die "CANNOT RUN: gh is not on PATH"

# Serialise against another copy of this script. It cannot protect against a
# bare 'gh auth switch' run elsewhere at the same moment, and nothing can:
# the active account is one global value.
exec 9>"${LOCK_FILE}" || die "CANNOT RUN: cannot create lock ${LOCK_FILE}"
flock -w 60 9 || die "CANNOT RUN: another as-owner run held ${LOCK_FILE} for 60s"

# Read the active account. gh 2.45 has no flag for this, so parse the report.
# Both streams are captured because gh has moved this output between them.
read_active_account() {
    local status
    status="$(gh auth status 2>&1)" || {
        printf '%s\n' "${status}" >&2
        return 1
    }
    printf '%s\n' "${status}" | awk '
        /Logged in to github\.com account / {
            for (i = 1; i <= NF; i++) if ($i == "account") acct = $(i + 1)
        }
        /Active account: true/ { print acct; exit }
    '
}

PREVIOUS_ACCOUNT="$(read_active_account)" \
    || die "CANNOT RUN: gh auth status failed, so the active account is unknown"
[ -n "${PREVIOUS_ACCOUNT}" ] \
    || die "CANNOT RUN: could not determine the active gh account; refusing to switch blind"

# A zero here would otherwise look like "not logged in" when it is really a
# changed output format, so check for the account line specifically.
gh auth status 2>&1 | grep -q "account ${TARGET_ACCOUNT} " \
    || die "CANNOT RUN: ${TARGET_ACCOUNT} is not logged into gh; run: gh auth login"

restore_account() {
    local rc=$?
    if [ "${PREVIOUS_ACCOUNT}" != "${TARGET_ACCOUNT}" ]; then
        if gh auth switch --user "${PREVIOUS_ACCOUNT}" >/dev/null 2>&1; then
            printf 'as-owner: restored active gh account to %s\n' "${PREVIOUS_ACCOUNT}" >&2
        else
            printf 'as-owner: WARNING failed to restore the active gh account to %s; it is still %s\n' \
                "${PREVIOUS_ACCOUNT}" "${TARGET_ACCOUNT}" >&2
        fi
    fi
    return "${rc}"
}

if [ "${PREVIOUS_ACCOUNT}" != "${TARGET_ACCOUNT}" ]; then
    trap restore_account EXIT INT TERM
    gh auth switch --user "${TARGET_ACCOUNT}" >/dev/null \
        || die "CANNOT RUN: gh auth switch to ${TARGET_ACCOUNT} failed"
    # Verify the effect, not the exit status.
    now="$(read_active_account)" || die "CANNOT RUN: cannot confirm the switch took effect"
    [ "${now}" = "${TARGET_ACCOUNT}" ] \
        || die "CANNOT RUN: switch reported success but the active account is ${now:-unknown}"
fi

"$@"
