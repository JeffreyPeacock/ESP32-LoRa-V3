#!/usr/bin/env bash
# Run by lxmd (-i) for every delivered LXMF message. lxmd passes the path of
# the received message file as $1. Appends a one-line record so a delivery can
# be confirmed without a GUI client.
set -euo pipefail
LOG="${LXMF_INBOX_LOG:-/tmp/claude-1000/lxmf-inbox.log}"
printf '%s  received: %s (%s bytes)\n' "$(date '+%F %T')" "${1:-<no path>}" \
    "$(stat -c%s -- "${1:-/dev/null}" 2>/dev/null || echo '?')" >> "${LOG}"
