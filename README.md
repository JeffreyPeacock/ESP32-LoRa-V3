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

Requires `pyenv` with the
[pyenv-virtualenv](https://github.com/pyenv/pyenv-virtualenv) plugin. If you only
need to configure a radio and will never compile firmware, run the installer with
`--skip-platformio` and skip a ~2 GB toolchain download.

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

## FTG1 configuration

Current state of the one board under our control. Values read from
`meshtastic --info`; the table is maintained by hand as tickets land, so treat
the device as authoritative if the two ever disagree.

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
| Stack | Meshtastic | #1 |
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
| Channel 1 downlink | **enabled** | name must literally be `mqtt` |

**Connectivity**

| | | Set by |
|---|---|---|
| Bluetooth | **off while WiFi is on** | ESP32 constraint, not a setting |
| WiFi | **enabled**, node has its own LAN address | #7 |
| GPS | none fitted | position is fixed, not sensed |
| MQTT | **enabled**, node connects directly | #5, #7 |
| MQTT broker | local mosquitto, anonymous | #7 (was the public broker in #5) |
| MQTT encryption | `true` | firmware default |
| MQTT topic root | `msh/US` | firmware default |
| MQTT JSON | **enabled** | required for injection — #7 |
| Meshtastic API | port 4403 on the LAN | how the phone app connects without BLE |
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
.claude/commands/       slash commands for issue and board workflow
doc/                    ticket Quick View, regenerated from the board
doc/mqtt-broker-vps.md  running and hardening a broker for the multi-site link
```

## Sites

The three radios are referred to by the nearest airport ident: **FTG1**, **SJC**
and **SNA**. Only FTG1 is under this repository owner's control; the other two
belong to other operators. Work is sequenced so that anything verifiable with
only FTG1 happens first.

## License

[MIT](LICENSE) — Copyright (c) 2026 Jeffrey Peacock
