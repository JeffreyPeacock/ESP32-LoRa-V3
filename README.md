# ESP32-LoRa-V3

Host tooling and bring-up firmware for the
[Heltec WiFi LoRa 32 V3](https://heltec.org/project/wifi-lora-32-v3/) —
an ESP32-S3 with a Semtech SX1262 LoRa radio and a 128×64 SSD1306 OLED.

The goal is text messaging between radios in Northern AZ, the CA Bay Area and
Orange County CA. This repository holds the parts that make a board usable from
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

## On range

Northern AZ to the Bay Area is roughly 900 km. There is no direct LoRa path at
that distance — the limit is the radio horizon and a hop limit capped at 7, not
transmit power. Linking two distant meshes requires a backbone carrying traffic
between gateways. Meshtastic implements that as MQTT, which needs IP reachability
between the two ends; what carries that IP is a free choice — public internet,
VPN, cellular, satellite, or a ham/AREDN link.

## Layout

```
platformio.ini          pinned platform, board, serial port and build flags
include/board_pins.h    pin map and the settings the variant header gets wrong
src/main.cpp            bring-up diagnostic firmware
scripts/                install, host setup, build and flash
scripts/lib/            shared shell helpers
```

## License

[MIT](LICENSE) — Copyright (c) 2026 Jeffrey Peacock
