# ESP32-LoRa-V3

Host tooling and bring-up firmware for the
[Heltec WiFi LoRa 32 V3](https://heltec.org/project/wifi-lora-32-v3/) —
an ESP32-S3 with a Semtech SX1262 LoRa radio and a 128×64 SSD1306 OLED.

The goal is text messaging between three radios, hundreds of km apart in Arizona
and California, referred to here by the nearest airport ident: **FTG1**, **SJC**
and **SNA**. This repository holds the parts that make a board usable from
a Linux command line: a one-shot toolchain installer, a root-level host setup
script, an unprivileged build-and-flash script, and a diagnostic firmware that
proves the hardware before any protocol work starts.

## Quick start

```bash
git clone git@github.com:JeffreyPeacock/ESP32-LoRa-V3.git
cd ESP32-LoRa-V3

./scripts/install-toolchain.sh      # PlatformIO, then a pyenv venv with meshtastic + esptool
./scripts/heltec-setup.sh setup     # udev rule; prompts for sudo once
./scripts/heltec-dev.sh check       # confirm the board is visible and usable
./scripts/heltec-dev.sh flash       # build, upload, then open the serial monitor
```

`install-toolchain.sh` uses `pyenv`, but the scripts do not — see [Python
environment](#python-environment) if you would rather use a plain virtualenv. If
you only need to configure a radio and will never compile firmware, run the
installer with `--skip-platformio` and skip a ~2 GB toolchain download.

## Python environment

Two of the tools this project drives are Python programs: the **Meshtastic CLI**,
which configures the radio, and **esptool**, which flashes it. They need to live
in a virtualenv somewhere. Which kind is your choice.

**This project is developed against pyenv**, because the author uses it across
every project on the machine, and `scripts/install-toolchain.sh` sets up exactly
that: a `meshtastic` virtualenv pinned to this directory with `pyenv local`. If
you already use pyenv, run the installer and stop reading here.

**Nothing in the scripts requires pyenv.** `resolve_venv_bin()` in
`scripts/lib/heltec-common.sh` accepts four layouts and takes the first that has
a `python` in it:

| Order | Location | When it applies |
|---|---|---|
| 1 | `$HELTEC_VENV/bin` | you set it explicitly; wins over everything |
| 2 | `.venv/bin` in the checkout | a plain virtualenv, the path below |
| 3 | `$VIRTUAL_ENV/bin` | you have already activated something |
| 4 | pyenv | nearest `.python-version`, then `$PYENV_ROOT/version` |

So if you do not use pyenv and do not want to install it:

```bash
python3 -m venv .venv
.venv/bin/pip install meshtastic esptool
```

That is the whole setup. **You do not have to activate it** — the scripts find
`.venv` in the checkout on their own, which is what makes this work from an IDE
or a cron job. `.venv/` is gitignored.

Two details worth knowing. A `.venv` in the checkout deliberately outranks an
activated `$VIRTUAL_ENV`, because it names *this* project while an active
environment could be anything; activating it gives the same answer either way. And
a candidate missing the tool being asked for is skipped rather than fatal, so a
half-built `.venv` falls through to a working environment instead of blocking it.

If nothing resolves, the scripts print all four locations they checked and what
each one was set to, rather than naming pyenv as though it were mandatory.

**PlatformIO is separate and is not in either virtualenv.** `pio` installs to
`~/.platformio` with its own private `penv` and is symlinked into `~/.local/bin`,
deliberately, so that every embedded project on the machine shares one PlatformIO
rather than one per project. Anything checking for the build toolchain must look
for `pio` on `PATH`, not inside the virtualenv. Compiling firmware needs it;
configuring a radio does not.

## Scripts

### `scripts/install-toolchain.sh` — run once, as yourself

Installs PlatformIO Core into `~/.platformio/penv`, symlinks `pio` into
`~/.local/bin`, then creates a pyenv virtualenv holding the Meshtastic CLI and
esptool and pins it to this directory.

Self-contained by design — it does not depend on anything else in this
repository, so it can be copied to a bare machine on its own.

| Option | |
|---|---|
| `--python-version X` | Python for the virtualenv (default 3.12.12) |
| `--venv-name NAME` | virtualenv name (default `meshtastic`) |
| `--penv-python PATH` | interpreter PlatformIO builds its penv from |
| `--project-dir DIR` | where to run `pyenv local` |
| `--skip-platformio` | virtualenv only, no embedded toolchain |
| `--reinstall-platformio` | rebuild `~/.platformio/penv` |

### `scripts/heltec-setup.sh` — host setup, needs root

Installs a udev rule for the board's CP2102N USB-UART bridge. Run it from a
normal shell; the commands that need root escalate through `sudo` themselves and
prompt once. `check` reads nothing privileged and never prompts.

```
setup                 install the udev rule, then run all checks
install / uninstall   the udev rule
check                 verify the host is ready
add-dialout [user]    add a user to the dialout group
disable-modemmanager  stop and disable ModemManager
dmesg                 recent cp210x / ttyUSB kernel messages
```

The rule exists mainly to tag the device `ID_MM_DEVICE_IGNORE`. Without it
ModemManager writes AT commands at the board's bootloader UART for several
seconds after every plug-in, and uploads fail with *"Failed to connect to
ESP32-S3."*

### `scripts/heltec-dev.sh` — build and flash, never as root

```
check           toolchain and device readiness
ports           attached boards with their stable by-path names
build / clean   pio run [-t clean]
upload [port]   write firmware and reset the board
monitor [port]  serial monitor at 115200
flash [port]    upload, then monitor — the usual edit-run loop
chip-id [port]  identify the attached ESP32-S3 with esptool
raw [port]      read the serial port with stty and cat, no PlatformIO
```

Refuses to run as root, because PlatformIO run as root leaves root-owned files in
`~/.platformio` and `.pio` that break the next build from a normal shell. The
port is autodetected when exactly one board is attached, and required when
several are.

### `scripts/meshtastic-listener.sh` — record and forward messages

Holds the serial port open, writes every text message the radio sees to a JSON
Lines ledger with its metadata, and forwards the ones addressed to this node by
email and SMS.

```
run         hold the port open and forward messages (the default)
self-test   send one test notification by email and SMS, then exit
check       report the config, the port, and whether anything holds it
tail        follow the ledger
  -c FILE   config file (default etc/secrets/listener.conf)
  -n        dry run: log what would be sent, send nothing
  -v        verbose
```

Copy `etc/listener.conf.example` to `etc/secrets/listener.conf` and fill it in.
The real file names an email address, which is why it lives under
`etc/secrets/` — gitignored as a whole directory.

**Recipients come from a book keyed by device**, so adding a person is a data
change rather than a config change, and a second radio can notify entirely
different people. One file drives **both email and SMS**:

```ini
[recipients]
file = etc/secrets/sms-phones.json
```

```json
[
  { "deviceId": "FTG1", "name": "Jeffrey",
    "phone": "5555550123", "email": "someone@example.com" }
]
```

An entry needs at least one of `phone` or `email` — neither is a mistake, not a
preference. Leave `[email] to` and `[sms] to` empty to route purely by device;
anything set there is copied on every message regardless of which radio heard
it. `[sms] phones_file` is still read when `[recipients]` is absent.

`deviceId` is matched against `[listen] device_id`, or — when that is blank —
against the radio's own short name read at connect time, which is one fewer
place for the two to drift apart. `gateway` and `enabled` are optional per
entry, so one person can sit on a different carrier or be switched off without
being deleted.

**Numbers are validated at startup**, not at send time: ten US digits, with a
leading `1` accepted and stripped. That strictness is deliberate — a carrier
gateway discards mail for an address it does not recognise without reporting
anything, so a typo would be indistinguishable from a message that was
delivered and never arrived. Each recipient gets their own message rather than
one with several addressees, so a single bad address cannot suppress the rest.

**Both notifications go through the local MTA.** Postfix on this host relays
outbound, and an SMS to a carrier gateway is just a short email to
`<number>@<gateway>`, so there is no second set of credentials. **Google Fi's
gateway is `<10 digits>@msg.fi.google.com`, confirmed delivering to a handset
on 2026-09-02** — it was an assumption until then, and the kind that fails
silently.

### What the message looks like, and what is not ours to decide

The SMS body and the email subject are `str.format` templates over the ledger
fields, so `{text}`, `{from_short}`, `{from_long}`, `{rx_snr}`, `{hops_away}`,
`{channel_name}` and the rest are all available:

```ini
[sms]
body_template = FTG1<-{from_short}: {text} ({rx_snr}dB)
```

`{text}` is truncated to whatever room the rest of the template leaves, so
anything placed after it survives and the total lands on `max_chars`. An
unknown field renders as `<name?>` and a malformed template falls back to the
bare text — a typo should look wrong, not stop the listener.

**Two things are decided outside this project.** Both surfaced on the first
real SMS:

- **The envelope sender must match the `From:` header.** The listener passes
  `sendmail -f` for this. Without it the envelope carries the invoking unix
  user, postfix rewrites envelope and header through `smtp_generic_maps`
  independently, and the two arrive as different addresses — which reads as
  forgery to a spam filter and breaks DMARC alignment.
- **Pick a sender whose domain authorises the relay.** Check before choosing:

  ```bash
  dig +short TXT flagstafftechgroup.org | grep spf1   # v=spf1 include:wonkware.com -all
  dig +short A mail.wonkware.com                      # must fall inside that
  ```

  A sender on a domain that does *not* list the relay fails SPF and scores
  worse than an unbranded address would.
- **The From address comes from postfix, not from `[sms] from`.**
  `smtp_generic_maps` rewrites the sender on the way out. A line like
  `@thishost  someone@example.com` in `/etc/postfix/generic` replaces whatever
  the listener set. Change it with a *more specific* entry — a full address
  beats a bare `@host` — then `postmap` it, and confirm the smarthost accepts
  that sender for the authenticated account. Many relays refuse a sender they
  do not own, so this needs the mail administrator, not just root.
- **A `[Potential Spam]` subject tag is added upstream.** Nothing on the
  sending host does it: `content_filter` is empty and no filter is running.
  It comes from the relay or the receiving carrier. A real subject helps a
  little; the actual fix is an allowlist wherever the tagging happens.

Four behaviours are deliberate and worth knowing:

- **Everything seen is recorded, forwarded or not**, with the reason in the
  `decision` field. A listener that silently drops what it chose not to forward
  cannot be debugged after the fact.
- **Packet ids are deduplicated.** A packet arrives once per neighbour that
  rebroadcasts it; without this, each hop would send its own email.
- **SMS has an hourly ceiling** (`max_per_hour`, default 20). A chatty channel
  or a rebroadcast loop should not be able to run up a bill.
- **A carrier SMS gateway drops messages silently** and gives no delivery
  receipt. If a message has to arrive, this is the wrong transport.

Run it as a service. The unit is **generated**, not committed, because it has
to carry this checkout's absolute path — a unit file with someone else's home
directory baked in is worse than none:

```bash
./scripts/meshtastic-listener.sh install-service      # user unit
systemctl --user enable --now meshtastic-listener
sudo loginctl enable-linger "$USER"                   # survive logout

./scripts/meshtastic-listener.sh install-service -s   # or a system unit
sudo systemctl enable --now meshtastic-listener
```

Either way it runs as **your account, never root** — the listener needs group
`dialout` and writes into the checkout, so root would leave root-owned files
that break the next ordinary run. Prefer `-s` on a headless always-on host: a
system unit starts at boot with no session and needs no lingering. See
[docs/raspberry-pi-deployment.md](docs/raspberry-pi-deployment.md).

**The radio serves one host at a time.** While the listener runs, `meshtastic
--info` and anything else that opens the port will fail. Stop it first:
`systemctl --user stop meshtastic-listener`.

`tests/test_listener.py` exercises the handling path with synthetic packets.
The mesh here carries almost no text traffic — a four-minute live capture
recorded none — so waiting for a real message is not a usable test.

## Firmware

`src/main.cpp` is a bring-up diagnostic. It transmits nothing. It reports the
chip and MAC, scans the OLED's I2C bus, initialises the SX1262, reads battery
voltage, and blinks. Run it on a new board before writing any protocol code, so a
later radio failure can be blamed on software rather than on a solder joint.

```
==== Heltec WiFi LoRa 32 V3 bring-up ====
chip      : ESP32-S3 rev 0 (major), 2 core(s) @ 240 MHz
flash     : 8388608 bytes @ 80000000 Hz
efuse mac : 44:1B:F6:FB:8E:00

-- I2C / OLED --
  i2c device at 0x3C  (SSD1306 OLED)

-- SX1262 --
  SX1262 up at 915.0 MHz, SF9/BW125/CR4:7

result: OLED ok, radio ok
```

`include/board_pins.h` is the pin authority. The PlatformIO variant header for
this board omits the battery-sense pins and calls the SX1262 interrupt `DIO0`,
which is an SX127x name — on this board it is **DIO1**. The header also records
the two settings that differ from RadioLib's defaults and that this board will
not transmit without: a **1.8 V TCXO** reference and **DIO2 as the RF switch**.

## Radios

Four boards exist; not all are attached at once. Only the two Heltecs can run
RNode — RNode firmware has no SAMD support at all.

| Board | MCU | Radio | MAC | Role |
|---|---|---|---|---|
| Heltec V3 — **FTG1** | ESP32-S3 | SX1262 | `44:1B:F6:FB:8E:00` | stationary node, Meshtastic 2.7.26 — listener on USB |
| Heltec V3 **#2** — **FTG2** | ESP32-S3 | SX1262 | `44:1B:F6:FA:AC:5C` | portable node, Meshtastic 2.7.26 — hosted by a phone over BLE, battery powered |
| SparkFun Pro RF ×2 | SAMD21 | RFM95 / SX1276 | — | point-to-point pair, separate work |

**Do not identify a board by its `ttyUSBn` number.** Both Heltecs report the
CP2102 factory serial `0001`, so `/dev/heltec-0001` and `/dev/serial/by-id/`
collapse them onto one name and will silently resolve to the wrong one. Confirm
with `esptool --port <dev> chip-id` and check the MAC. The Reticulum configs
address the boards by `/dev/serial/by-path/`, which names the physical socket.

Heltec #2 needs USB only for power and flashing; the phone is its host.

### What is on the band here

915 MHz ISM, and more crowded than it looks:

| Frequency | Used by | Notes |
|---|---|---|
| 902.3–914.9 MHz | LoRaWAN US915 uplink | 125/500 kHz channels |
| 906.875 MHz | Meshtastic LongFast US | SF11/BW250 |
| **915.000 MHz** | **our RNodes** | BW 125 kHz, SF8, CR5 |
| 914.875 / 915.000 MHz | 86% of US RNodes generally | measured from the discovery network |
| 920.000 MHz | the Pro RF pair | BW 125 kHz, SF7, CR5, sync `0x4A` |
| 923.3–927.5 MHz | LoRaWAN US915 downlink | |

**The separation was measured, not assumed.** With the Pro RF pair transmitting
at 920.0, FTG1 reported interference at **−74 dBm with 0.0% channel load**, and
announced successfully — against **−22 to −26 dBm** from unrelated LoRa
equipment sharing our channel earlier. Five megahertz at 125 kHz bandwidth is
forty channel widths, and it shows.

Note the consequence recorded in `docs/Reticulum-exploration-notes.md`: **do not
move our link off 915.000** to dodge local interference. It is the frequency
another RNode operator would most likely arrive on.

## Live configuration

**Both Heltecs run Meshtastic 2.7.26** as of 2026-09-01. RNode was saved off
first; `etc/rnode/RESTORE.md` has everything needed to put it back.

| | FTG1 — stationary | FTG2 — portable |
|---|---|---|
| Node ID | `!f6fb8e00` | `!f6faac5c` |
| Name | `FLG Tech Group 01` / `FTG1` | `FLG Tech Group 02` / `FTG2` |
| Host | USB to this machine, running the listener | a phone over BLE |
| Region / preset | US, `LONG_FAST` | US, `LONG_FAST` |
| Bluetooth | enabled | enabled, **random PIN shown on the OLED** |
| WiFi / MQTT | off / off | off / off |
| Uplink / downlink | off on all channels | off on all channels |
| Position | fixed, a public landmark | **fixed, the same landmark as FTG1** |
| `position_precision` | 13 (km scale) | 13 (km scale) |
| GPS | none fitted | none fitted |
| Serial path | `…usb-0:3:1.0-port0` | `…usb-0:5.3.3.3:1.0-port0` |

Both carry the same three channels: the default LongFast primary, `mqtt`, and
**`ftg-priv`** with a generated key.

**The whole path is verified on hardware**, 2026-09-02: a message typed on the
phone reached a handset as an SMS, through

> phone → BLE → FTG2 → 915 MHz LoRa → FTG1 → USB → listener → relay → email
> and SMS

about two seconds end to end, at SNR 5.75 / RSSI −7 over 0 hops. The ledger row
records `direct: true`, `pki_encrypted: true`, `email_sent: true`,
`sms_sent: true`.

**A direct message is addressed to the node, not posted to a channel.** In the
app the three channels are group conversations keyed `0^all` / `1^all` /
`2^all`; a DM to FTG1 is a separate conversation keyed `8!f6fb8e00`, where 8 is
`PKC_CHANNEL_INDEX`, a sentinel rather than a real channel. `ftg-priv` is
private in that strangers cannot read it, but it is still a broadcast to
everyone holding the key. With `dm_only = true` a channel post is recorded and
**not** forwarded.
FTG2 got them by applying FTG1's channel URL, so the keys match exactly.

**FTG2's fixed position is deliberate.** It is a portable node with no GPS, set
to report the same landmark as FTG1 rather than where it actually is. Note the
consequence: it will keep claiming that location while out in the field, and
enabling "provide phone location" in the app would override it with your real
position on a channel that neighbouring gateways can read.

Revert to RNode with `etc/rnode/RESTORE.md`. The node IDs survive any reflash —
they are derived from the MAC.

### Meshtastic configuration, as last set (#1–#7)

Read from `meshtastic --info` on 2026-08-19 and preserved in
`etc/secrets/ftg1-2026.08.19.config.yaml`. This was the **normal operating
configuration**: Bluetooth to a phone, LoRa to the local mesh, no network
dependency.

**Hardware**

| | | |
|---|---|---|
| Board | Heltec WiFi LoRa 32 V3 | |
| MCU | ESP32-S3, rev v0.2, 2 cores @ 240 MHz | |
| Radio | Semtech SX1262 | 1.8 V TCXO, DIO2 drives the RF switch |
| Flash | 8 MB embedded (GD) | no PSRAM |
| MAC | `44:1B:F6:FB:8E:00` | |
| USB bridge | CP2102N, `10c4:ea60` | **not** the ESP32-S3 native USB |
| Serial port | `/dev/ttyUSB0` @ 115200 | pinned in `platformio.ini` |

**Firmware**

| | | Set by |
|---|---|---|
| Stack | Meshtastic — **not currently loaded** | #1 |
| Version | `2.7.26.54e0d8d` | #1 |
| Target | `heltec-v3` | #1 |
| Node ID | `!f6fb8e00` | derived from the MAC, not configurable |
| Owner name | `FLG Tech Group 01` / `FTG1` | #5 |
| Role | `CLIENT` | default |

**LoRa**

| | | Set by |
|---|---|---|
| Region | `US` (902–928 MHz) | #2 |
| Fixed position | set; coordinates **not** recorded here | #5 |
| Modem preset | `LONG_FAST` | default |
| Hop limit | `3` | default, max 7 |
| TX enabled | `true` | |
| RX boosted gain | `true` | |
| Primary channel | index 0, unnamed | default LongFast |
| Channel PSK | default (well known, not private) | |
| Channel 0 uplink | **enabled** | #5 |
| Channel 0 downlink | disabled | deliberate — see below |
| Channel 1 | `mqtt`, random PSK | downlink target — #7 |
| Channel 1 downlink | **off** | re-enable only for injection work — see below |

**Connectivity**

| | | Set by |
|---|---|---|
| Bluetooth | **enabled** — phone connects over BLE | normal operating mode |
| WiFi | **off** | enabling it disables BLE — ESP32 constraint |
| GPS | none fitted | position is fixed, not sensed |
| MQTT | **off** | optional; the mesh needs no internet |
| MQTT broker | `mqtt.meshtastic.org` as `meshdev` | preset, unused while MQTT is off |
| MQTT encryption | `true` | firmware default |
| MQTT topic root | `msh/US` | firmware default |
| MQTT JSON | enabled | only matters for injection — #7 |
| Meshtastic API | port 4403, **only when WiFi is on** | how the app connects without BLE |
| Web UI | ports 80/443 | built in |

Three entries above are choices rather than defaults left alone:

- **Channel 0 downlink stays off.** Uplink publishes what this node hears;
  downlink would rebroadcast public-internet traffic onto the local RF mesh,
  which is antisocial on a shared default channel. Downlink gets enabled later
  on a dedicated channel, where it only carries our own traffic.
- **The channel is still stock LongFast with the default key**, which is what
  any other Meshtastic user in the area is on. That is what made the survey (#3)
  productive. It is not private; a dedicated channel with a generated key comes
  later.
- **The fixed position is a nearby public landmark**, not the operator's
  address, and the coordinates are not committed. Channel 0 also carries
  `position_precision: 13`, so what leaves the radio is coarsened to roughly km
  scale regardless.

## Bridging a mesh to the internet

Meshtastic joins two meshes that cannot hear each other over RF by relaying
through an MQTT broker. Uplink publishes what a node hears; downlink takes
messages from the broker and transmits them over LoRa. Both directions are
needed for a two-site link.

**Downlink only works when the node has its own network connection.** Through
the phone proxy it fails — the message reaches the phone and kills the app's
MQTT client, reproducibly, and nothing is transmitted. On the node's own WiFi
the same payload works.

| Transport | Uplink | Downlink |
|---|---|---|
| Phone proxy over BLE | works | **fails** |
| Node's own WiFi | works | works |

So whichever node terminates a remote link needs WiFi or Ethernet of its own. A
phone-proxied node can send outward but cannot be reached from another site.

Injecting a message requires a channel named literally `mqtt` with downlink
enabled, `mqtt.json_enabled`, and a publish to `msh/US/2/json/mqtt/`:

```json
{"from": 4143681024, "type": "sendtext", "payload": "hello"}
```

The public broker will not do this — it restricts JSON downlink — so this needs
a broker you control.

### Reaching a headless node

WiFi and BLE are mutually exclusive on ESP32, so a WiFi node is not reachable
over Bluetooth. It is still reachable three other ways: the phone app can add it
as a **network device on port 4403**, a browser can use the **web UI on port
80**, and the CLI takes `--host <ip>` in place of `--port`.

## Power and runtime

From the Heltec datasheet (Rev 1.1, Table 3.4), whole board:

| Mode | Current |
|---|---:|
| Receive (TX disabled) | **90 mA** |
| Bluetooth | 115 mA |
| Transmit @ 22 dBm | 230 mA |
| Sleep, on battery | 15 µA |

On a 3000 mAh cell that is **roughly one day** of ordinary use — listening,
paired to a phone, relaying for the mesh. The ESP32 staying awake to receive
dominates; transmitting is brief enough that its higher current barely matters.

Multi-day runtimes need Meshtastic's `is_power_saving`, which switches off
Bluetooth, WiFi and the screen — useful for an unattended beacon, not for a
device you message from.

USB and battery switch over automatically: with USB attached the board runs from
USB and charges the pack.

## On range

FTG1 to SJC is roughly 900 km. There is no direct LoRa path at that distance —
the limit is the radio horizon and a hop limit capped at 7, not transmit power.
Linking two distant meshes requires a backbone carrying traffic between
gateways. Meshtastic implements that as MQTT, which needs IP reachability
between the two ends; what carries that IP is a free choice — public internet,
VPN, cellular, satellite, or a ham/AREDN link.



## Layout

```
platformio.ini          pinned platform, board, serial port and build flags
include/board_pins.h    pin map and the settings the variant header gets wrong
src/main.cpp            bring-up diagnostic firmware
scripts/                install, host setup, build and flash
scripts/lib/            shared shell helpers
tests/                  listener tests, no radio required
etc/listener.conf.example  template for etc/secrets/listener.conf
etc/rnode/              RNode parameters and how to restore them
.claude/commands/       slash commands for issue and board workflow
docs/                    ticket Quick View, regenerated from the board
docs/datasheets/         vendor PDFs for every chip on the board
docs/mqtt-broker-vps.md  running and hardening a broker for the multi-site link
docs/Reticulum-exploration-notes.md   RNode and Reticulum findings (#8)
docs/Reticulum-Overview.md            short primer on the stack
docs/Reticulum-value-and-limits.md    what it is for, and what it will not do
docs/aredn-as-a-transport.md          reference: AREDN, and why Part 97 rules it out here
docs/config-tools.md                  GUI alternatives to the CLIs, and how to install each
docs/raspberry-pi-deployment.md       moving the radio and listener to a Pi 4
docs/meshtastic-rf-survey.md          what was measured on the air around FTG1 (#3)
etc/reticulum/          Reticulum config for FTG1, and its backups
etc/secrets/            device config exports and anything else local — gitignored
etc/firmware/           vendor images kept for rollback — gitignored
.claude_artifacts/       transcripts and local notes — gitignored in full
```

## Hardware references

Every PDF below is mirrored in `docs/datasheets/` so a developer can work
offline, and because vendor download URLs move. The links are the authoritative
copies — check them if a figure here looks wrong.

**This board is the one Heltec calls HTIT-WB32LA.** Both the V3 and the V3.2
datasheets are included: the two revisions differ in ways that matter, most
notably the `ADC_CTRL` polarity that gates battery sense, so the schematics are
worth comparing rather than assuming.

| Document | Rev | Pages | Source |
|---|---|---:|---|
| Heltec WiFi LoRa 32 (V3) datasheet | 1.1 | 15 | [HTIT-WB32LA_V3(Rev1.1).pdf](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/HTIT-WB32LA_V3\(Rev1.1\).pdf) |
| Heltec WiFi LoRa 32 (V3.2) datasheet | 1.1 | 15 | [HTIT-WB32LA_V3.2.pdf](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/HTIT-WB32LA_V3.2.pdf) |
| Heltec V3 schematic | — | 1 | [HTIT-WB32LA(F)_V3_Schematic_Diagram.pdf](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/HTIT-WB32LA\(F\)_V3_Schematic_Diagram.pdf) |
| Heltec V3.1 schematic | — | 1 | [HTIT-WB32LA(F)_V3.1_Schematic_Diagram.pdf](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/HTIT-WB32LA\(F\)_V3.1_Schematic_Diagram.pdf) |
| Heltec V3.2 schematic | — | 1 | [WiFi_LoRa_32_V3.2_Schematic_Diagram.pdf](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/WiFi_LoRa_32_V3.2_Schematic_Diagram.pdf) |
| Semtech SX1261/2 radio | 1.2 | 111 | [SX1262_datasheet.pdf](https://cdn.sparkfun.com/assets/6/b/5/1/4/SX1262_datasheet.pdf) |
| Espressif ESP32-S3 datasheet | 2.2 | 87 | [esp32-s3_datasheet_en.pdf](https://www.espressif.com/sites/default/files/documentation/esp32-s3_datasheet_en.pdf) |
| Espressif ESP32-S3 technical reference manual | 1.8 | 1531 | [esp32-s3_technical_reference_manual_en.pdf](https://www.espressif.com/sites/default/files/documentation/esp32-s3_technical_reference_manual_en.pdf) |
| Solomon Systech SSD1306 OLED controller | 1.1 | 65 | [SSD1306.pdf](https://cdn-shop.adafruit.com/datasheets/SSD1306.pdf) |
| Silicon Labs CP2102N USB-UART bridge | — | 48 | [cp2102n-datasheet.pdf](https://www.silabs.com/documents/public/data-sheets/cp2102n-datasheet.pdf) |

Two of these answer questions that come up repeatedly:

- **Power figures come from Heltec Table 3.4**, page 11 of the V3 datasheet, and
  they are whole-board measurements. Do not rebuild them by adding up the
  SX1262 and ESP32-S3 numbers — that undercounts by roughly half, because it
  misses the regulator, the OLED and the USB bridge. See [Power and
  runtime](#power-and-runtime).
- **The SX1262 datasheet is the authority for the TCXO and RF-switch settings**
  that `include/board_pins.h` sets. Getting either wrong lets the radio
  initialise cleanly and transmit nothing.

Beyond the silicon:

- [Heltec WiFi LoRa 32 (V3) product page](https://heltec.org/project/wifi-lora-32-v3/)
  and [documentation](https://docs.heltec.org/en/node/esp32/wifi_lora_32/index.html)
- [Heltec V3 download directory](https://resource.heltec.cn/download/WiFi_LoRa_32_V3/) — where the PDFs above come from
- [Meshtastic firmware](https://github.com/meshtastic/firmware) and [documentation](https://meshtastic.org/docs/)
- [RadioLib](https://github.com/jgromes/RadioLib) — the driver `src/main.cpp` uses
- [Reticulum](https://reticulum.network/) and [RNode firmware](https://github.com/markqvist/RNode_Firmware) — the likely end state

## Sites

The three radios are referred to by the nearest airport ident: **FTG1**, **SJC**
and **SNA**. Only FTG1 is under this repository owner's control; the other two
belong to other operators. Work is sequenced so that anything verifiable with
only FTG1 happens first.

## License

[MIT](LICENSE) — Copyright (c) 2026 Jeffrey Peacock
