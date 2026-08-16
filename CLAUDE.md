# Project instructions

Working notes for this repository. These are facts that were expensive to
establish and are easy to get wrong from memory or from generic documentation.

## What this project is

A Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) at **FLG**, intended to exchange text
messages with radios at **SJC** and **SNA**. The three sites are referred to by
the nearest airport ident throughout; they are hundreds of km apart, in Arizona
and California.

Two constraints shape everything:

- **Only FLG is under our control.** The other two belong to other people who
  may not be reachable. Prefer work that can be completed and verified solo.
- **A backbone is required between sites.** Meshtastic caps hop limit at 7
  (default 3) and each hop is one RF link of a few km; FLG to SJC is ~900 km.
  The gap cannot be closed with more LoRa hops. Meshtastic bridges meshes with
  MQTT, which needs IP reachability between gateways — the transport under that
  IP is a free choice (public internet, VPN, cellular, ham/AREDN).

**Current direction:** Meshtastic first, to learn the hardware and find out
whether anyone else is on the air within range of FLG. Reticulum/RNode is the
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
- Battery sense needs `ADC_CTRL` (GPIO37) driven LOW to connect the divider.
  `VBAT_DIVIDER` is 4.9 and is **uncalibrated** — verify against a meter before
  trusting any reading.
- The OLED is on its own I2C bus (SDA 17 / SCL 18), not the header pins.

Verified on the bench: OLED answers at 0x3C, SX1262 initialises at 915 MHz,
MAC `44:1B:F6:FB:8E:00`, ESP32-S3 rev v0.2, 8 MB flash, no PSRAM.

`ESP.getEfuseMac()` returns the MAC **little-endian** — octet 1 of the printed
address is the low byte. Printing high-byte-first silently reverses it.

FLG's Meshtastic node ID is **`!f6fb8e00`** — the low four bytes of the MAC. It
is derived, not configured, so it survives reflashing and factory reset. This is
the address the other sites need.

## Node name is deliberately the factory default

FLG runs the stock owner name `Meshtastic 8e00` / `8e00`. **This is a decision,
not an oversight — do not "fix" it.**

`longName` and `shortName` go out in every NodeInfo packet. Once they reach the
public broker they cannot be withdrawn: services that ingest that broker keep
what they heard, and a later rename does not rewrite their history. The site
codes FLG/SJC/SNA exist partly for obfuscation, so broadcasting one as a node
name would work against that.

Renaming is free while MQTT is off and permanent once it is on, so the decision
point is #5, not #2. Ask before setting a name.

## There is an active mesh in range of FLG (#3)

Surveyed 2026-08-15 with the stock LongFast channel and default key. **FLG is
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
| `!9c594d28` (`FLG1`) | 1 | Heltec Mesh Pocket; name suggests a local node |
| `085e15cb` | — | The relay both traceroutes pass through — the local mesh leans on it |

Traceroute shows **asymmetric routing**, which is normal and worth remembering
when a one-way test looks like a failure:

```
towards:  !f6fb8e00 --> efa18420 (-15.5dB)
back:     efa18420 --> 085e15cb (-3.5dB) --> !f6fb8e00 (-1.0dB)
```

**Do not commit other operators' positions.** Several nodes broadcast lat/lon.
Node IDs are already public on the mesh and on MQTT maps; coordinates are
someone else's location and stay out of this repository.

### Timestamps from the node are not wall-clock

With no GPS and no network time, `lastHeard` is seeded from the **firmware build
epoch**, so `--nodes` renders live traffic as "1 month ago". Our own node reads
the same way, which is the giveaway. Trust relative ordering, not dates — and
use a live capture when recency matters.

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

Labels: `hardware` `meshtastic` `mqtt` `reticulum` `rf` `coordination`
`decision`. Milestones: **Solo bring-up** (verifiable with only FLG) and
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
| `/priority-review` | Rebuild `doc/ticket-priority-review.md`, the at-a-glance Quick View |
| `/create-plan` | Enter plan mode for a task |

## Commits

**Do not add Claude attribution to commits** — no `Co-Authored-By` trailer, no
"Generated with" line. This is a standing instruction from the repository owner.

## Repository is public

No credentials, WiFi SSIDs, or channel pre-shared keys in tracked files. Exported
Meshtastic device configuration contains channel PSKs and is gitignored.
