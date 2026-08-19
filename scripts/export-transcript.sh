#!/usr/bin/env bash
#
# Export a Claude Code session transcript to readable text, with secrets masked.
#
# Claude Code keeps each session as JSONL under ~/.claude/projects/<encoded-cwd>/.
# That is machine-readable, enormous, and full of nested tool payloads. This
# renders it as plain text and, by default, masks the secret material that ends
# up in a session log by accident -- CLI tools echo what they set, and config
# exports contain keys.
#
# Masking is ON by default and has to be switched off deliberately. That is the
# right way round: a transcript is easy to paste somewhere public.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/heltec-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/heltec-common.sh"

CLAUDE_HOME="${CLAUDE_HOME:-${HOME}/.claude}"
OUT_DIR="${PROJECT_DIR}/.claude_artifacts/transcripts"
SESSION=''
OUT_PATH=''
MASK=1
KEEP_THINKING=1
MAX_TOOL_IN=2000
MAX_TOOL_OUT=3000
declare -a EXTRA_SECRETS=()
# Literals to mask, one per line. Preferred over --secret: a value typed on the
# command line lands in shell history AND in the next transcript.
SECRETS_FILE="${PROJECT_DIR}/.claude_artifacts/mask-secrets.txt"

usage() {
    cat <<USAGE
Usage: $(basename -- "$0") [options]

Render this project's Claude Code session log as readable text, with secrets
masked. Defaults to the most recently modified session.

  --session ID|PATH   session UUID, or a path to a .jsonl (default: newest)
  --out PATH          output file (default: <out-dir>/YYYY.MM.DD-transcript.txt)
  --out-dir DIR       default ${OUT_DIR#"${PROJECT_DIR}"/}
  --secret STRING     also mask this literal; repeatable (prefer --secrets-file)
  --secrets-file PATH literals to mask, one per line, # for comments
                      (default: .claude_artifacts/mask-secrets.txt if present)
  --no-mask           do NOT mask anything (think before using this)
  --no-thinking       omit assistant reasoning blocks
  --max-tool-in N     truncate tool inputs at N chars (default ${MAX_TOOL_IN})
  --max-tool-out N    truncate tool results at N chars (default ${MAX_TOOL_OUT})
  --list              list this project's sessions and exit
  -h, --help          this message

Always masked: Meshtastic channel URLs (they encode every channel PSK), WiFi
PSKs, YAML psk/password/wifiPsk values, and hex PSK arguments.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --session)      SESSION="${2:?}"; shift 2 ;;
        --out)          OUT_PATH="${2:?}"; shift 2 ;;
        --out-dir)      OUT_DIR="${2:?}"; shift 2 ;;
        --secret)       EXTRA_SECRETS+=("${2:?}"); shift 2 ;;
        --secrets-file) SECRETS_FILE="${2:?}"; shift 2 ;;
        --no-mask)      MASK=0; shift ;;
        --no-thinking)  KEEP_THINKING=0; shift ;;
        --max-tool-in)  MAX_TOOL_IN="${2:?}"; shift 2 ;;
        --max-tool-out) MAX_TOOL_OUT="${2:?}"; shift 2 ;;
        --list)         SESSION='__list__'; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

# Claude Code encodes the project path by replacing both / and . with -
encoded_project_dir() {
    printf '%s\n' "${PROJECT_DIR}" | sed 's|[/.]|-|g'
}

LOG_DIR="${CLAUDE_HOME}/projects/$(encoded_project_dir)"
[[ -d ${LOG_DIR} ]] || die "no session logs for this project at ${LOG_DIR}"

list_sessions() {
    local f
    for f in "${LOG_DIR}"/*.jsonl; do
        [[ -e ${f} ]] || continue
        printf '  %s  %6s  %s\n' \
            "$(date -r "${f}" +'%Y-%m-%d %H:%M')" \
            "$(du -h "${f}" | cut -f1)" \
            "$(basename -- "${f}" .jsonl)"
    done
}

if [[ ${SESSION} == '__list__' ]]; then
    section "sessions for ${PROJECT_DIR##*/}"
    list_sessions
    exit 0
fi

# Resolve which log to render
if [[ -z ${SESSION} ]]; then
    SRC="$(find "${LOG_DIR}" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' \
           | sort -rn | head -n 1 | cut -d' ' -f2-)"
    [[ -n ${SRC} ]] || die "no .jsonl session logs in ${LOG_DIR}"
elif [[ -f ${SESSION} ]]; then
    SRC="${SESSION}"
else
    SRC="${LOG_DIR}/${SESSION}.jsonl"
    [[ -f ${SRC} ]] || die "no such session: ${SESSION} (try --list)"
fi

[[ -n ${OUT_PATH} ]] || OUT_PATH="${OUT_DIR}/$(date +'%Y.%m.%d')-transcript.txt"
mkdir -p -- "$(dirname -- "${OUT_PATH}")"

# Refuse to write somewhere git would track. A transcript is exactly the kind of
# file that carries a key into a public repository.
#
# The check only applies INSIDE the work tree: git reports any path outside it as
# "not ignored", which is true but irrelevant -- git cannot track /tmp either.
ABS_OUT="$(realpath -m -- "${OUT_PATH}")"
if [[ ${ABS_OUT} == "${PROJECT_DIR}"/* ]] \
   && git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if ! git -C "${PROJECT_DIR}" check-ignore -q "${ABS_OUT}" 2>/dev/null; then
        warn "${OUT_PATH} is inside the repository and NOT gitignored."
        warn "Transcripts routinely contain credentials. Add it to .gitignore first,"
        warn "or pass --out to a path that is ignored."
        die "refusing to write a transcript to a tracked location"
    fi
fi

section 'export'
info "source : ${SRC}"
info "output : ${OUT_PATH}"
info "masking: $([[ ${MASK} -eq 1 ]] && echo on || echo 'OFF -- secrets will be written in clear')"

# EXTRA_SECRETS is an array, and bash cannot export arrays -- exporting it
# passes nothing at all, silently. Flatten it into a separate scalar first.
OUT="${OUT_PATH}"
if [[ -f ${SECRETS_FILE} ]]; then
    while IFS= read -r line; do
        [[ -z ${line} || ${line} == '#'* ]] && continue
        EXTRA_SECRETS+=("${line}")
    done < "${SECRETS_FILE}"
    info "secrets file: ${SECRETS_FILE} ($(grep -cvE '^\s*(#|$)' "${SECRETS_FILE}") entries)"
fi

SECRETS_BLOB="$(printf '%s\n' ${EXTRA_SECRETS[@]+"${EXTRA_SECRETS[@]}"})"
export SRC OUT MASK KEEP_THINKING MAX_TOOL_IN MAX_TOOL_OUT SECRETS_BLOB

if ! python3 - <<'PYTHON'
import json, os, re, sys, datetime

SRC   = os.environ['SRC']
DST   = os.environ['OUT']
MASK  = os.environ['MASK'] == '1'
THINK = os.environ['KEEP_THINKING'] == '1'
MAXIN = int(os.environ['MAX_TOOL_IN'])
MAXOUT= int(os.environ['MAX_TOOL_OUT'])
EXTRA = [s for s in os.environ.get('SECRETS_BLOB','').split('\n') if s]

RULE = '=' * 78

def stamp(o):
    t = o.get('timestamp')
    if not t: return ''
    try:
        return datetime.datetime.fromisoformat(t.replace('Z','+00:00')) \
                 .astimezone().strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        return str(t)

def clip(v, n):
    s = v if isinstance(v, str) else json.dumps(v, indent=1, default=str)
    return s if len(s) <= n else s[:n] + f"\n… [truncated, {len(s)-n} more chars]"

counts = {'user':0,'assistant':0,'thinking':0,'tool_use':0,'tool_result':0,'bad':0}
out = []

for line in open(SRC, encoding='utf-8'):
    line = line.strip()
    if not line: continue
    try:
        o = json.loads(line)
    except Exception:
        counts['bad'] += 1
        continue
    if o.get('type') not in ('user','assistant'): continue
    msg = o.get('message')
    if not isinstance(msg, dict): continue
    role = msg.get('role','?')
    counts[role] = counts.get(role,0)+1
    out.append(f"\n{RULE}\n{role.upper()}   {stamp(o)}\n{RULE}")

    content = msg.get('content')
    if isinstance(content, str):
        out.append(content); continue
    for b in (content or []):
        if not isinstance(b, dict):
            out.append(str(b)); continue
        t = b.get('type')
        if t == 'text':
            out.append(b.get('text',''))
        elif t == 'thinking':
            counts['thinking'] += 1
            if THINK:
                out.append(f"\n--- [thinking] ---\n{b.get('thinking','').strip()}\n--- [/thinking] ---")
        elif t == 'tool_use':
            counts['tool_use'] += 1
            out.append(f"\n>>> TOOL CALL: {b.get('name')}\n{clip(b.get('input',{}), MAXIN)}")
        elif t == 'tool_result':
            counts['tool_result'] += 1
            c = b.get('content')
            if isinstance(c, list):
                c = "\n".join(x.get('text','') if isinstance(x,dict) else str(x) for x in c)
            out.append(f"\n<<< TOOL RESULT{' (ERROR)' if b.get('is_error') else ''}:\n{clip(c or '', MAXOUT)}")
        else:
            out.append(f"\n[{t}]\n{clip(b, 600)}")

body = (f"{RULE}\nClaude Code session transcript\n"
        f"source  : {SRC}\n"
        f"exported: {datetime.datetime.now():%Y-%m-%d %H:%M}\n"
        f"masking : {'on' if MASK else 'OFF'}\n{RULE}\n") + "\n".join(out) + "\n"

# One definition of what a secret looks like, used BOTH to mask and to verify.
# If these two ever diverge the check becomes theatre, so they share a list.
PATTERNS = [
    ('channel URL',
     r'(https://meshtastic\.org/e/#)[A-Za-z0-9_\-]{20,}'),
    ('wifi psk (echoed)',
     r'(wifi[_ ]?psk\s*(?:to|=|:)\s+)(?!\*)(\S{4,})'),
    ('wifi psk (argument)',
     r'(--set\s+network\.wifi_psk\s+)(?!\*)([\'"]?[^\'"\s]{4,}[\'"]?)'),
    ('wifiPsk (yaml)',
     r'(wifiPsk\s*:\s+)(?!\*)(\S{4,})'),
    ('psk (yaml)',
     r'(\bpsk\s*:\s+)(?!\*)([A-Za-z0-9+/=]{16,})'),
    ('psk (hex arg)',
     r'(--ch-set\s+psk\s+)(0x[0-9a-fA-F]{16,})'),
    ('mqtt password',
     r'(mqtt\.password\s+)(?!\*)(\S{4,})'),
    # security.privateKey from `meshtastic --export-config`. This is the node's
    # PKI identity: it decrypts direct messages addressed to us and can be used
    # to impersonate the node. It leaked into a session on 2026-08-19 because
    # nothing here matched it.
    ('node private key',
     r'(privateKey\s*:\s*(?:base64:)?)(?!\*)([A-Za-z0-9+/=]{16,})'),
    # Not a secret, but it names the operator's home network.
    ('wifi ssid (yaml)',
     r'(wifiSsid\s*:\s+)(?!\*)(\S+)'),
    ('wifi ssid (argument)',
     r'(--set\s+network\.wifi_ssid\s+)(?!\*)([\'"]?[^\'"\s]+[\'"]?)'),
]

masked = {}
if MASK:
    for label, pat in PATTERNS:
        body, n = re.subn(pat, lambda m: m.group(1) + '***', body)
        if n: masked[label] = n
    for s_ in EXTRA:
        n = body.count(s_)
        if n:
            body = body.replace(s_, '***')
            masked[f'--secret {s_[:6]}…'] = n

# Verify with the same patterns. Anything still matching is a genuine leak,
# not a prose false positive, because the patterns require a value to follow.
residual = {}
for label, pat in PATTERNS:
    hits = re.findall(pat, body)
    if hits: residual[label] = len(hits)

open(DST,'w',encoding='utf-8').write(body)

print(f"  rendered {counts['user']} user / {counts['assistant']} assistant turns, "
      f"{counts['tool_use']} tool calls, {counts['thinking']} thinking blocks")
if counts['bad']:
    print(f"  WARNING: {counts['bad']} unparseable lines skipped")
if MASK:
    print("  masked  : " + (", ".join(f"{k} x{v}" for k,v in masked.items()) if masked else "nothing matched"))
print(f"  size    : {len(body):,} chars, {body.count(chr(10)):,} lines")
if MASK:
    if residual:
        print("  RESIDUAL: " + ", ".join(f"{k} x{v}" for k,v in residual.items()))
        sys.exit(3)
    print("  residual: none — no pattern still matches a value")
PYTHON
then
    die 'masking left secret material in the output — not safe to share'
fi

ok 'export complete'
info 'the scan only knows the patterns above — skim the file before sharing it'

report_result
