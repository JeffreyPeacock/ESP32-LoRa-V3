# Project instructions

Working notes for this repository. These are facts that were expensive to
establish and are easy to get wrong from memory or from generic documentation.

## What this project is

A Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) at **FTG1**, intended to exchange text
messages with radios at **SJC** and **SNA**. The three sites are referred to by
the nearest airport ident throughout; they are hundreds of km apart, in Arizona
and California.

Two constraints shape everything:

- **Only FTG1 is under our control.** The other two belong to other people who
  may not be reachable. Prefer work that can be completed and verified solo.
- **A backbone is required between sites.** Meshtastic caps hop limit at 7
  (default 3) and each hop is one RF link of a few km; FTG1 to SJC is ~900 km.
  The gap cannot be closed with more LoRa hops. Meshtastic bridges meshes with
  MQTT, which needs IP reachability between gateways — the transport under that
  IP is a free choice (public internet, VPN, cellular, ham/AREDN).

**Current direction:** Meshtastic first, to learn the hardware and find out
whether anyone else is on the air within range of FTG1. Reticulum/RNode is the
likely end state, because it is an actually routed hybrid — transport nodes
with path tables, transport-agnostic interfaces, and LXMF propagation nodes
that hold messages for offline recipients. Meshtastic has none of those: its
MQTT bridge glues two flood domains together and queues nothing.

## Hardware facts

The PlatformIO variant header for this board is incomplete and one name in it is
wrong. `include/board_pins.h` is the authority; use it, not the variant.

- The radio is an **SX1262**, and its interrupt line is **DIO1 on GPIO14**. The
  variant header calls it `DIO0`, which is an SX127x name.
- The board clocks the radio from a **1.8 V TCXO** and switches its RF front end
  from **DIO2**. Both differ from RadioLib's defaults. Get either wrong and the
  radio initialises cleanly, reports no error, and transmits nothing.
- `Vext` (GPIO36) is **active LOW** and gates the OLED supply.
- Battery sense is gated by `ADC_CTRL` (GPIO37), and **the polarity depends on
  board revision** — LOW enables it pre-V3.2, HIGH on V3.2 and later. The wrong
  choice does not error: the divider stays disconnected and the ADC reads ~0,
  which is indistinguishable from an empty JST. `src/main.cpp` probes both.
- **A voltage on the battery sense line does not prove a battery is fitted.**
  With USB attached and no pack, the charger output floats near 4.2 V with
  nothing to sink it, and Meshtastic duly reports ~4.14 V and ~96%. Confirm a
  pack by looking at the connector, never from a reading.
- `VBAT_DIVIDER` is 4.9 and is **uncalibrated** — verify against a meter before
  trusting any reading.
- The OLED is on its own I2C bus (SDA 17 / SCL 18), not the header pins.

Verified on the bench: OLED answers at 0x3C, SX1262 initialises at 915 MHz,
MAC `44:1B:F6:FB:8E:00`, ESP32-S3 rev v0.2, 8 MB flash, no PSRAM.

`ESP.getEfuseMac()` returns the MAC **little-endian** — octet 1 of the printed
address is the low byte. Printing high-byte-first silently reverses it.

FTG1's Meshtastic node ID is **`!f6fb8e00`** — the low four bytes of the MAC. It
is derived, not configured, so it survives reflashing and factory reset. This is
the address the other sites need.

## FTG1's on-air identity

| | |
|---|---|
| `longName` | `FLG Tech Group 01` |
| `shortName` | `FTG1` |
| Node ID | `!f6fb8e00` |

Chosen in #5 and checked for collisions against the 71 nodes then known. `FTG1`
is deliberately distinct from the neighbouring `FLG1` (Brilliant Mobile, 10 km)
and `FLAG` (Brilliant Mesh) — those are the operators most likely to be confused
with us.

**This is now public and permanent.** It has been uplinked to the public broker,
and services that ingest that broker keep what they heard; a later rename will
not rewrite their history. Renaming the device is still trivial, but the old
name cannot be recalled.

## FTG1 broadcasts a fixed position

FTG1 has no GPS. It carries a **fixed position** set with
`--setlat/--setlon/--setalt`, chosen as a nearby public landmark rather than the
operator's address.

**The coordinates are not recorded in this repository.** They approximate where
the operator lives, and the same rule applied to other operators' positions
applies to ours. Read them from the device with `meshtastic --info` when needed.

Two things blunt the disclosure, and it is worth knowing both:

- Channel 0 carries `position_precision: 13`, so what leaves the radio is
  quantised to roughly km scale, not the stored value.
- The stored fix is a public landmark to begin with.

Note the ordering consequence: once a position is broadcast, a location-hinting
**node name adds little further disclosure** — the position packet is already
more precise than the name. The name decision was made under the older
assumption that no position was being sent.

## There is an active mesh in range of FTG1 (#3)

Surveyed 2026-08-15 with the stock LongFast channel and default key. **FTG1 is
not isolated.** This changes planning: real RF peers exist to test against, so
link behaviour no longer has to wait on SJC.

- **14 nodes** entered the NodeDB within ~35 minutes of setting the region.
- **25 packets from 11 distinct senders** in a single 5-minute capture.
- Typical signal **SNR −5 to −6 dB, RSSI ≈ −97 dBm**; the best peer sits at
  **+0.75 dB**.
- Hop spread: 1 node at 0 hops, 2 at 1, 5 at 2, 3 at 3.

Useful peers, by node ID — these are stable and worth reusing as test targets:

| Node | Hops | Note |
|---|---|---|
| `!efa18420` | 0 | Direct neighbour. Busiest sender. |
| `!fe716141` (`MRC`) | 0 | Direct, SNR −11 dB |
| `!9c594d28` (`FLG1`) | 1 | Heltec Mesh Pocket, ~1.4 km |
| `!085e15cb` (`Eldn`) | 0 | Elden-Rptr-1-Mesh — the relay everything leaves town through |
| `!1fa06b14` (`tr`) | 1 | ROUTER 100 km WSW; the next hop after Eldn toward Prescott |

### The path off the Flagstaff bowl is two routers, not one

Traceroute to a Prescott-area node:

```
towards: FTG1 --> !085e15cb (1.0dB) --> !1fa06b14 (-5.75dB) --> !b03b38dc (4.5dB)
back:    !b03b38dc --> !1fa06b14 (-2.75dB) --> !085e15cb (-12.25dB) --> FTG1
```

`Eldn` does not see Prescott. It spans **103.7 km SW to `!1fa06b14`**, which serves
the Prescott area. Do not attribute the whole southwest reach to one node.

### The link to Eldn is diffraction, not line of sight

Eldn sits on the **north** side of Mt. Elden at 2705 m; FTG1 is on the south side
at 2103 m. The summit (2835 m) lies 58% along the 4.64 km path and stands **384 m
above the line of sight — twenty times the first Fresnel radius**. Deeply
obstructed, and yet it is a reliable 0-hop link at ~0 dB SNR.

**On this terrain, `hopsAway: 0` says nothing about line of sight.** A 915 MHz
LoRa link with SF11 has enough budget to diffract over a sharp ridge. Do not
infer geometry from hop counts, and do not infer a path from elevation alone.

Traceroute shows **asymmetric routing**, which is normal and worth remembering
when a one-way test looks like a failure:

```
towards:  !f6fb8e00 --> efa18420 (-15.5dB)
back:     efa18420 --> 085e15cb (-3.5dB) --> !f6fb8e00 (-1.0dB)
```

**Do not commit other operators' positions.** Several nodes broadcast lat/lon.
Node IDs are already public on the mesh and on MQTT maps; coordinates are
someone else's location and stay out of this repository.

### The node clock, and why timestamps lie until you set it

FTG1 has no GPS and no battery-backed RTC. With no time source it seeds its clock
from the **firmware build epoch**, so `--nodes` renders live traffic as "1 month
ago". Our own node reads the same way, which is the giveaway.

Fix it directly:

```bash
meshtastic --set-time            # uses the host clock; verified skew 0.00 h
```

**It does not survive a power cycle** — there is no RTC to hold it, so the node
re-seeds from the build epoch on every boot. Two things set it automatically, so
this is mostly a bench-only chore: the phone app sets the time when it connects
over BLE, and mesh peers share time with each other. Set it by hand when working
over serial with no phone attached, and re-set it after any reboot.

Until it is set, trust relative ordering rather than dates, and use a live
capture when recency matters.

### Peer positions are not committed

Many peers broadcast lat/lon. Those are other operators' locations. They are
kept in `docs/peers.local.md`, which `.gitignore` excludes via `docs/*.local.*` —
useful for making contact locally, not ours to publish. Node IDs are fine to
record; coordinates are not.

**The NodeDB ages entries out, so a scan is not a record.** `peers-report.sh`
accumulates everything ever seen into `docs/peers.local.json` and merges it back
on each run; nodes the radio has forgotten appear under "Heard before, no longer
in the NodeDB". The ledger carries the same coordinates as the report and the
script refuses to run unless **both** are gitignored.

**Local secrets live in `etc/secrets/`**, ignored as a whole directory rather
than by file pattern. Device config exports go there: they carry channel PSKs,
the WiFi PSK, and `security.privateKey`, which is the node's PKI identity.

## Normal operating mode is BLE, no network

The default and expected state of FTG1 is **Bluetooth to a phone, LoRa to the
local mesh, WiFi off, MQTT off**. Nothing about ordinary Meshtastic use needs an
internet connection — the mesh found in #3 runs entirely over RF.

WiFi and MQTT get switched on for bridging work and switched back off. If a
session leaves the board on WiFi, the phone cannot pair, because BLE is disabled
whenever WiFi is up. **Restore the normal mode when finishing bridging work:**

```bash
meshtastic --set network.wifi_enabled false --set mqtt.enabled false
meshtastic --ch-set downlink_enabled false --ch-index 1
```

Keep `downlink_enabled` off on every channel during normal use. Downlink over
the BLE proxy is what triggers the queue-saturation bug below, and it is
worthless without a broker anyway.

## MQTT downlink needs the node's own network (#7)

Proven on the bench, and it constrains the architecture rather than being a
configuration detail:

| Transport | Uplink (mesh → broker) | Downlink (broker → mesh) |
|---|---|---|
| Phone proxy over BLE | works (#5) | **fails** |
| Node's own WiFi | works | **works** (#7) |

With `mqtt.proxy_to_client_enabled`, a downlink message reaches the phone and
**kills the app's MQTT client** — reproducibly, ~6 s after each publish, with a
~18 s reconnect. Nothing is transmitted. On the node's own WiFi the identical
payload works first time.

**Consequence for the multi-site link:** whichever node terminates a remote link
must have its own WiFi or Ethernet. A phone-proxied node can send outward but
cannot be reached from another site, which is the half that matters for
receiving. This governs #9 and #10.

The working injection, verified in the serial log:

```
[mqtt] JSON payload FTG1 injection proof, length 20
[mqtt] handleReceived(LOCAL) (... fr=0xf6fb8e00 ... Portnum=1)
[mqtt] Expand short PSK #1 ... Use AES128 key!
[RadioIf] Started Tx (... encrypted len=42)
[RadioIf] Completed sending
```

Requirements, all of them mandatory:

- a channel named **literally `mqtt`** with `downlink_enabled` (the name is the
  subscription trigger), reboot after adding it
- `mqtt.json_enabled = true`
- publish to `msh/US/2/json/mqtt/` as
  `{"from": <decimal node num>, "type": "sendtext", "payload": "..."}`
- FTG1's node num is **4143681024** (`!f6fb8e00` in hex)

Keep `downlink_enabled` **off** on the primary channel. Downlink there would
rebroadcast public-internet traffic onto the shared local mesh. It belongs only
on the dedicated `mqtt` channel.

### Broker gotchas that cost real time

- **The public broker will not do this.** It restricts JSON downlink, hence a
  private broker.
- **amqtt is MQTT 3.1.1 only; the Meshtastic phone app speaks MQTT 5.0.** The
  broker answers `Unsupported protocol version` and the app reports
  `UNSUPPORTED_PROTOCOL_VERSION`. Use **mosquitto** (2.0.18 handles both).
- **amqtt's `allow-anonymous: true` still rejects a client that supplies a
  username.** It permits clients sending *no* credentials. The node was sending
  `meshdev`/`large4cats` inherited from the public broker and got
  `Not authorized`, with no session and therefore nothing in the broker log.
- **mosquitto 2.x defaults to localhost-only and denies anonymous.** It needs
  `listener 1883 0.0.0.0` and `allow_anonymous true` in `/etc/mosquitto/conf.d/`.

## The diagnostic firmware is deaf to the mesh

`src/main.cpp` sets `RADIOLIB_SX126X_SYNC_WORD_PRIVATE` (0x12) at SF9/BW125.
Meshtastic uses a different sync word and SF11/BW250. **The SX1262 only raises a
receive interrupt for a matching sync word and modulation**, so the diagnostic
firmware cannot hear a single packet of the 115-node mesh around it. That is
correct behaviour, not a fault — do not go hunting for a broken radio.

The same mechanism is why a Meshtastic node repeats nothing but Meshtastic:

- **What it can hear** is a hardware filter — sync word, SF, BW, CR, frequency.
  LoRaWAN uses sync word 0x34 and SF7–SF10 at 125/500 kHz, so it is rejected in
  the modem before firmware sees a byte.
- **What it forwards** is firmware — hop limit, dedup, `rebroadcastMode`.

With `rebroadcastMode: ALL` (our default) a node relays packets on channels it
**cannot decrypt**. That is how a shared LongFast carrier serves everyone's
private channels — and why strangers' radios carry our `mqtt` channel traffic.

Repeating is not a property of the radio. Our `CLIENT` node already relays for
others; `ROUTER` mainly means well-sited infrastructure that rebroadcasts
promptly.

## Reaching a headless node on WiFi

WiFi and BLE are mutually exclusive on ESP32, so a node using its own WiFi is
unreachable over Bluetooth. It is not unreachable in general — it serves three
interfaces on the LAN:

| Port | What | Use |
|---|---|---|
| 4403 | Meshtastic API | **Add as a "network device" in the phone app** — full messaging |
| 80/443 | built-in web UI | browser |
| — | — | `meshtastic --host <ip>` instead of `--port /dev/ttyUSB0` |

The app's "add a network device" feature expects a **radio** on 4403. Pointing
it at an MQTT broker on 1883 makes it send Meshtastic stream framing to the
broker, which logs `Invalid remaining length bytes:0x94949494` — `0x94` is the
Meshtastic start byte. That is a wrong-address symptom, not a broker fault.

The node's address comes from DHCP, so set a reservation on the router before
depending on it.

### WiFi failure codes worth recognising

`Reason: 15 - 4WAY_HANDSHAKE_TIMEOUT`, looping every ~8 s, means the **PSK is
wrong** — the node found the AP and failed authentication. It is not a band or
SSID problem. Read it with a raw serial capture; the protobuf API hides these
logs. Note the ESP32-S3 is **2.4 GHz only**, so also confirm the SSID exists on
2.4 GHz.

## Which firmware is on the board

The board holds one firmware at a time and there is no way to tell from the
outside. Check before assuming:

```bash
./scripts/heltec-dev.sh raw     # tap RST, read the banner, Ctrl-C
```

`==== Heltec WiFi LoRa 32 V3 bring-up ====` is the PlatformIO diagnostic;
Meshtastic and RNode announce themselves in their own boot logs.

**`./scripts/heltec-dev.sh flash` overwrites whatever is there** with the
PlatformIO diagnostic. That is the intended escape hatch for proving hardware,
but run `meshtastic --export-config` first if there is configuration worth
keeping — channel PSKs included, which is why those exports are gitignored.

As of #1 the board runs Meshtastic **2.7.26.54e0d8d**, target `heltec-v3`.

## Power draw, from the datasheet (not estimated)

Heltec datasheet Rev 1.1 Table 3.4, page 11, whole board, measured USB-powered.
Vendor PDFs for every chip are mirrored in `docs/datasheets/`; read them there
rather than from memory or from a web search:

| Mode | Current |
|---|---:|
| RX (TX disabled) | **90 mA** |
| Bluetooth | 115 mA |
| WiFi scan / AP | 115 / 150 mA |
| TX @ 22 dBm | 230 mA |
| Sleep, on battery | 15 µA |

On a 3000 mAh pack that is roughly **one day**, not two. Estimating from
component datasheets gave 55 mA and was about half the real figure — the
whole-board number includes the regulator, the OLED and the USB bridge. Use the
table, not arithmetic from the SX1262 alone.

Two consequences worth remembering:

- **The screen and BLE cost more than transmitting.** TX is 230 mA but the duty
  cycle is tiny; the ESP32 staying awake to listen dominates.
- Multi-day runtimes need `is_power_saving`, which disables Bluetooth, WiFi and
  the screen. That is a beacon, not a messaging device.

The datasheet also confirms **USB/battery automatic switching**: with USB
attached the board runs from USB and charges the pack. USB together with the 5V
pin is the one combination that is not allowed.

## Serial port

The USB-C port does **not** reach the ESP32-S3's native USB. It goes to a
CP2102N bridge on UART0, so the board enumerates as `10c4:ea60` → `/dev/ttyUSBn`,
never as `303a:1001`. The stock PlatformIO board definition declares the native
USB hwid, so port autodetect finds no match and falls back to the first serial
port on the system. `platformio.ini` pins `/dev/ttyUSB*` for this reason.

ModemManager probes every new tty with AT commands and collides with esptool for
several seconds after plug-in. `scripts/heltec-setup.sh` installs a udev rule
tagging the device `ID_MM_DEVICE_IGNORE`. This is the load-bearing part of that
rule; the `MODE`/`GROUP` lines are redundant with Ubuntu's own defaults.

The `/dev/heltec-*` symlink does **not** identify a specific board — Heltec ships
these CP2102Ns with the factory serial `0001`, so every board produces
`/dev/heltec-0001`. With more than one attached, use `/dev/serial/by-path/`.

## Toolchain layout

Three environments with distinct jobs. Do not merge them.

| Path | What | Provides |
|---|---|---|
| `~/.pyenv/versions/meshtastic` | pyenv virtualenv, pinned by `.python-version` | `meshtastic` CLI, `esptool`, `python` |
| `~/.platformio` | **not** a venv — PlatformIO's data dir | `platforms/`, `packages/` (toolchains), `penv/` |
| `~/.local/bin/pio` | symlink into `~/.platformio/penv/bin` | `pio` on PATH everywhere |

`pio` deliberately lives **outside** the project virtualenv so every embedded
project on the machine shares one PlatformIO install. Code that checks for the
toolchain must look for `pio` on PATH, not inside the venv.

`scripts/install-toolchain.sh` reproduces all of this on a fresh machine.

**pyenv is this machine's choice, not a project requirement.** The scripts
resolve the interpreter through `resolve_venv_bin()` in
`scripts/lib/heltec-common.sh`, which tries `$HELTEC_VENV`, then `.venv/` in the
checkout, then `$VIRTUAL_ENV`, then pyenv — first one with a `python` wins, and
a candidate missing the requested tool is skipped rather than fatal. A
contributor can `python3 -m venv .venv && .venv/bin/pip install meshtastic
esptool` and never install pyenv. Do not reintroduce a hard-coded
`~/.pyenv/versions/meshtastic` path; `peers-report.sh` had one and it was the
only thing standing between a new developer and a working checkout.

## Shell script conventions

All scripts must pass `shellcheck -x` with no output. Run it before finishing.

- **Never `... | grep -q` under `set -o pipefail`.** `grep -q` exits at the first
  match, the upstream command dies of SIGPIPE, and the pipeline returns 141
  despite the match succeeding. This has already caused two real bugs here. Read
  into a variable and use a herestring.
- **Watch for functions shadowing commands.** A status helper named `head()` once
  shadowed `/usr/bin/head` in the same script. shellcheck does not catch this.
- Every subcommand is **idempotent** — re-running changes nothing already in the
  desired state, and the udev rule is rewritten only when its content differs.
- `heltec-setup.sh` escalates **per command** through a `SUDO` array rather than
  re-execing under sudo, so `check` never prompts for a password.
- `heltec-dev.sh` **refuses to run as root** — PlatformIO as root leaves
  root-owned files in `~/.platformio` and `.pio` that break the next build.
- Shell startup files cannot be relied on for pyenv: `runuser -l` and `su -` give
  a *non-interactive* login shell, and Ubuntu's `~/.bashrc` returns on its first
  line for those, so `pyenv init` never runs. Resolve interpreters directly.

## The second radio lives in its own project

A **SparkFun LoRa Gateway 1-Channel (ESP32)** turned up on `/dev/ttyUSB1` and is
documented in `../../Sparkfun/ESP32-LoRa-1-Gateway`, not here.

**None of the hardware facts above apply to it.** It is an ESP32-D0WDQ6 with an
RFM95W — an SX1276 — behind a CH340C. No 1.8 V TCXO, no DIO2 RF switch, and its
interrupt genuinely is DIO0. Its radio sits at NSS 16 / RST 5 / DIO0 26, which
matches no stock Meshtastic or RNode target, so it cannot join a link test
without custom firmware. It is relevant to #14 because it already is a working
LoRaWAN gateway.

## Issue tracker and board

Issues live in `JeffreyPeacock/ESP32-LoRa-V3`; the board is **LoRa Wide-Area
Mesh**, project **#10**, owned by the **user** `JeffreyPeacock` — GraphQL uses
`user(login:)`, not `organization(login:)`, and `gh project` needs
`--owner JeffreyPeacock`.

**Priority is a board field here, not a label.** Do not create `priority:pN`
labels.

| Thing | ID |
|---|---|
| Project | `PVT_kwHOAdChXs4BgeW5` |
| Status field | `PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y` |
| Status options | Backlog `fc0746ee` · Prioritized `7db529ed` · Ready `0559bd80` · In Progress `082c573d` · Completed `5241f608` |
| Priority field | `PVTSSF_lAHOAdChXs4BgeW5zhfGh_A` |
| Priority options | p1 `768405dd` · p2 `bded9378` · p3 `baa61257` · p4 `90f2d0b0` · p5 `77dadab6` |
| Repo node | `R_kgDOT5oIVQ` |

Labels: `hardware` `meshtastic` `mqtt` `reticulum` `rf` `lorawan` `coordination`
`decision`. Milestones: **Solo bring-up** (verifiable with only FTG1) and
**Multi-site link** (needs an operator at SJC or SNA). The milestone test is
verifiability, not subject matter.

The board holds ~12 items, so a single `gh project item-list` is complete and
cheap — the paging workarounds needed on larger boards do not apply here. Still
filter server-side where the option exists.

## Branches and verification

Branch prefixes: `fix/`, `feat/`, `docs/`, `chore/`. Documentation-only changes
may go straight to `main`.

**There is no CI.** An empty `statusCheckRollup` proves nothing — never report
that checks passed when none ran. These local gates are the only gates:

```bash
shellcheck -x scripts/*.sh scripts/lib/*.sh    # must produce NO output
pio run                                        # must end in [SUCCESS]
./scripts/heltec-dev.sh check                  # when hardware is involved
```

Never report a hardware result that was not observed. If the board was not
attached, say the check did not run.

## Slash commands

`.claude/commands/` — adapted from the CaptureServer project, with the board
IDs, gates and hardware realities of this repo.

| Command | Does |
|---|---|
| `/new-issue` | File an issue, label it, set milestone, add to the board, set Status and Priority |
| `/fix-ticket N` | Work one ticket end to end: board → branch → gates → PR |
| `/fix-ready` | Drain the Ready column, ordered around which firmware the board can hold |
| `/backlog-audit` | Groom the board: priorities, milestones, stale assumptions |
| `/merge-pr N` | Verify locally, squash-merge, move tickets to Completed |
| `/board-check` | Verify host, serial path and radio; report which firmware is loaded |
| `/priority-review` | Rebuild `docs/ticket-priority-review.md`, the at-a-glance Quick View |
| `/export-transcript` | Render the session log as text, with secrets masked |
| `scripts/peers-report.sh` | Rebuild `docs/peers.local.md` from the radio's NodeDB |
| `/create-plan` | Enter plan mode for a task |
| `/trim-claude-md` | Bring this file back under 40k without losing findings |
| `/prep-compaction` | Fold session findings into the docs before context is lost |

## Session transcripts carry secrets

`scripts/export-transcript.sh` renders a session log as text and masks secrets
while doing it. Masking is on by default and the script refuses to write to any
path inside the repository that is not gitignored.

This is not hypothetical. A single session here captured a WiFi PSK -- because
the Meshtastic CLI **echoes the value it sets**, so "run it yourself so it stays
out of the transcript" does not work -- and a Meshtastic channel URL, which
encodes **every channel's pre-shared key**.

Project-specific literals go in `.claude_artifacts/mask-secrets.txt`, one per
line. Prefer that to `--secret` on the command line: an argument lands in shell
history and then in the *next* transcript.

The script verifies its own output by re-running the masking patterns against
the finished file, so the check and the fix share one definition and cannot
drift apart. It still only knows the patterns it was given.

## Commits

**Do not add Claude attribution to commits** — no `Co-Authored-By` trailer, no
"Generated with" line. This is a standing instruction from the repository owner.

## Repository is public

No credentials, WiFi SSIDs, or channel pre-shared keys in tracked files. Exported
Meshtastic device configuration contains channel PSKs and is gitignored.
