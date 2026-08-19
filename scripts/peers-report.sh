#!/usr/bin/env bash
#
# Write docs/peers.local.md: every node this radio has heard, with distance and
# bearing from our own position.
#
# The reference position is read FROM THE DEVICE rather than hard-coded. That is
# better engineering and better privacy: this script is committed, and our fixed
# position approximates where the operator lives.
#
# The output is deliberately NOT committed -- it carries other operators'
# coordinates. The script refuses to write anywhere git would track.

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/heltec-common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/heltec-common.sh"

OUT_PATH="${PROJECT_DIR}/docs/peers.local.md"
PORT=''
HOST=''
NEAR_MI=15

usage() {
    cat <<USAGE
Usage: $(basename -- "$0") [options]

Render every node this radio has heard to ${OUT_PATH#"${PROJECT_DIR}"/}.

  --port PATH    serial device (default: autodetect)
  --host IP      talk over TCP instead of serial (node must be on WiFi)
  --out PATH     output file
  --near MI      "realistic contact" threshold (default ${NEAR_MI})
  -h, --help     this message
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="${2:?}"; shift 2 ;;
        --host) HOST="${2:?}"; shift 2 ;;
        --out)  OUT_PATH="${2:?}"; shift 2 ;;
        --near) NEAR_MI="${2:?}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ ${EUID} -ne 0 ]] || die 'do not run this as root'

if [[ -z ${HOST} && -z ${PORT} ]]; then
    PORT="$(resolve_port '')"
fi

mkdir -p -- "$(dirname -- "${OUT_PATH}")"

# Peer coordinates belong to other people. Never let this land in git.
ABS_OUT="$(realpath -m -- "${OUT_PATH}")"
if [[ ${ABS_OUT} == "${PROJECT_DIR}"/* ]] \
   && git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${PROJECT_DIR}" check-ignore -q "${ABS_OUT}" 2>/dev/null \
        || die "${OUT_PATH} is not gitignored — it would publish other operators' positions"
fi

section 'peers report'
info "source : ${HOST:-${PORT}}"
info "output : ${OUT_PATH}"

# Any virtualenv carrying the meshtastic package will do -- pyenv, a plain
# .venv in the checkout, or one already activated. See lib/heltec-common.sh.
VENV_BIN="$(resolve_venv_bin meshtastic)" || die "$(venv_hint)"

OUT_PATH="${OUT_PATH}" PORT="${PORT}" HOST="${HOST}" NEAR_MI="${NEAR_MI}" \
"${VENV_BIN}/python" - <<'PYTHON'
import os, math, json, datetime, sys
import meshtastic, meshtastic.serial_interface, meshtastic.tcp_interface
import time

OUT  = os.environ['OUT_PATH']
NEAR = float(os.environ['NEAR_MI'])
host, port = os.environ.get('HOST',''), os.environ.get('PORT','')

iface = (meshtastic.tcp_interface.TCPInterface(hostname=host) if host
         else meshtastic.serial_interface.SerialInterface(devPath=port))
time.sleep(5)

me    = iface.getMyNodeInfo() or {}
mypos = me.get('position', {}) or {}
REF   = (mypos.get('latitude'), mypos.get('longitude'))
REFALT= mypos.get('altitude')
nodes = iface.nodes or {}
myid  = (me.get('user') or {}).get('id')

def geo(lat, lon):
    if None in REF or lat is None: return None
    # Mean Earth radius in statute miles, so every distance below is miles.
    R=3958.7613; p1,p2=math.radians(REF[0]),math.radians(lat)
    dp,dl=math.radians(lat-REF[0]),math.radians(lon-REF[1])
    a=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    mi=2*R*math.asin(math.sqrt(a))
    y=math.sin(dl)*math.cos(p2); x=math.cos(p1)*math.sin(p2)-math.sin(p1)*math.cos(p2)*math.cos(dl)
    b=(math.degrees(math.atan2(y,x))+360)%360
    pts=['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW']
    return mi, mi*1.609344, pts[round(b/22.5)%16]

now = int(time.time())
def age(lh):
    if not lh: return 'never'
    s = max(0, now-lh)
    return f'{s//60}m' if s<3600 else (f'{s//3600}h' if s<86400 else f'{s//86400}d')

rows=[]
for nid, n in nodes.items():
    if nid == myid: continue
    u=n.get('user',{}) or {}; p=n.get('position',{}) or {}; m=n.get('deviceMetrics',{}) or {}
    rows.append(dict(id=nid, short=u.get('shortName') or '', long=u.get('longName') or '',
                     hw=u.get('hwModel'), role=u.get('role'), snr=n.get('snr'),
                     hops=n.get('hopsAway'), heard=n.get('lastHeard'),
                     lat=p.get('latitude'), lon=p.get('longitude'), alt=p.get('altitude'),
                     batt=m.get('batteryLevel')))

withpos = sorted([r for r in rows if r['lat'] is not None], key=lambda r: geo(r['lat'],r['lon'])[0])
nopos   = sorted([r for r in rows if r['lat'] is None],
                 key=lambda r: (r['hops'] is None, r['hops'] if r['hops'] is not None else 99))
routers = [r for r in rows if (r.get('role') or '')=='ROUTER']
near    = [r for r in withpos if geo(r['lat'],r['lon'])[0] <= NEAR]

def hop(r): return str(r['hops']) if r['hops'] is not None else '?'
def snr(r): return str(r['snr']) if r['snr'] is not None else '—'
def mapl(r): return f"[map](https://www.google.com/maps?q={r['lat']:.5f},{r['lon']:.5f})"
def alt(r):
    a = r['alt']
    return f'{a*3.28084:.0f} ft ({a} m)' if a is not None else '—'

L=[]
L.append('# Peers heard by this node — local notes\n')
L.append('**Not committed.** Positions are other operators\' locations, broadcast on the public\n'
         'mesh. Fine for making contact locally; not ours to publish. Gitignored via `docs/*.local.md`.\n')
L.append(f"**Snapshot:** {datetime.datetime.now():%Y-%m-%d %H:%M} · {len(rows)} peers · "
         f"{len(withpos)} with position · {len(routers)} ROUTER\n")
if None in REF:
    L.append('> This node has no position set, so distances and bearings are omitted.\n')
else:
    L.append(f'Distance and bearing are from this node\'s own position '
             f'(altitude {REFALT*3.28084:.0f} ft / {REFALT} m),\n'
             'read from the device rather than hard-coded. NodeDB entries age out, so counts\n'
             'move between refreshes — this is a snapshot.\n')

if routers:
    L.append('## Infrastructure (role = ROUTER)\n')
    L.append('| Node | Short | Name | Hops | SNR | Dist | Brg | Alt | Heard |')
    L.append('|---|---|---|:---:|---:|---:|:---:|---:|---:|')
    for r in sorted(routers, key=lambda r: (r['hops'] if r['hops'] is not None else 99)):
        g = geo(r['lat'], r['lon']) if r['lat'] is not None else None
        d = f'{g[0]:.1f} mi ({g[1]:.1f} km)' if g else '—'
        b = g[2] if g else '—'
        L.append(f"| `{r['id']}` | **{r['short']}** | {r['long']} | {hop(r)} | {snr(r)} | "
                 f"{d} | {b} | {alt(r)} | {age(r['heard'])} |")
    L.append('')

L.append('## Peers with a known position\n')
L.append('| Node | Short | Name | Hops | SNR | Dist | Brg | Lat | Lon | Alt | Heard | Map |')
L.append('|---|---|---|:---:|---:|---:|:---:|---:|---:|---:|---:|---|')
for r in withpos:
    g = geo(r['lat'], r['lon'])
    L.append(f"| `{r['id']}` | **{r['short']}** | {r['long']} | {hop(r)} | {snr(r)} | "
             f"{g[0]:.1f} mi ({g[1]:.1f} km) | {g[2]} | {r['lat']:.5f} | {r['lon']:.5f} | {alt(r)} | "
             f"{age(r['heard'])} | {mapl(r)} |")

L.append('\n## Peers with no position broadcast\n')
L.append('| Node | Short | Name | Hardware | Hops | SNR | Heard |')
L.append('|---|---|---|---|:---:|---:|---:|')
for r in nopos:
    L.append(f"| `{r['id']}` | **{r['short']}** | {r['long']} | {r['hw'] or '—'} | "
             f"{hop(r)} | {snr(r)} | {age(r['heard'])} |")

L.append(f'\n## Within {NEAR:.0f} mi — realistic in-person contacts\n')
if near:
    for r in near:
        g = geo(r['lat'], r['lon'])
        L.append(f"- **{r['short']}** — {r['long']} (`{r['id']}`), "
                 f"{g[0]:.2f} mi ({g[1]:.2f} km) {g[2]}, "
                 f"{hop(r)} hop, SNR {snr(r)}, {alt(r)}, {mapl(r)}")
else:
    L.append(f'- none positioned within {NEAR:.0f} mi')

L.append('\n## Notes\n')
L.append('- Positions carry whatever precision each operator configured; treat them as approximate.')
L.append('- Timestamps are only meaningful while the device clock is set — the phone sets it over')
L.append('  BLE, otherwise `meshtastic --set-time` after each reboot.')
L.append('- Regenerate with `./scripts/peers-report.sh`.\n')

open(OUT,'w',encoding='utf-8').write("\n".join(L)+"\n")
print(f"  {len(rows)} peers, {len(withpos)} positioned, {len(routers)} routers, {len(near)} within {NEAR:.0f} mi")
iface.close()
PYTHON

ok "wrote ${OUT_PATH}"
report_result
