# Project instructions

Working notes for this repository. These are facts that were expensive to
establish and are easy to get wrong from memory or from generic documentation.

## What this project is

A Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262) in Northern AZ, intended to
exchange text messages with radios in the CA Bay Area and Orange County, CA.

Two constraints shape everything:

- **Only the Northern AZ board is under our control.** The other two belong to
  other people who may not be reachable. Prefer work that can be completed and
  verified solo.
- **A backbone is required between sites.** Meshtastic caps hop limit at 7
  (default 3) and each hop is one RF link of a few km; Northern AZ to the Bay
  Area is ~900 km. The gap cannot be closed with more LoRa hops. Meshtastic
  bridges meshes with MQTT, which needs IP reachability between gateways — the
  transport under that IP is a free choice (public internet, VPN, cellular,
  ham/AREDN).

**Current direction:** Meshtastic first, to learn the hardware and find out
whether anyone else is on the air in Northern AZ. Reticulum/RNode is the likely
end state, because it is an actually routed hybrid — transport nodes with path
tables, transport-agnostic interfaces, and LXMF propagation nodes that hold
messages for offline recipients. Meshtastic has none of those: its MQTT bridge
glues two flood domains together and queues nothing.

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

## Commits

**Do not add Claude attribution to commits** — no `Co-Authored-By` trailer, no
"Generated with" line. This is a standing instruction from the repository owner.

## Repository is public

No credentials, WiFi SSIDs, or channel pre-shared keys in tracked files. Exported
Meshtastic device configuration contains channel PSKs and is gitignored.
