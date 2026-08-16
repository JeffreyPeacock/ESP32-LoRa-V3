# Verify the radio end to end

Confirm the host, the serial path and the radio hardware are all working, and report what firmware
the board is currently running. This is the hardware equivalent of an integration test — run it
before believing any negative result, and after any toolchain or udev change.

Takes about a minute. Requires the board attached over USB-C with a **data** cable.

`$ARGUMENTS` may name a port (e.g. `/dev/ttyUSB0`); otherwise it is autodetected.

## Step 1 — Host and toolchain

```bash
./scripts/heltec-dev.sh check
```

Expected: `pio` resolves from `~/.local/bin`, `meshtastic` and `esptool` from the pyenv `meshtastic`
virtualenv, exactly one board attached, readable and writable, port free, and
`ID_MM_DEVICE_IGNORE=1` set.

Common failures and what they mean:

| Symptom | Cause |
|---|---|
| `no USB device 10c4:ea60` | Board unplugged, or a charge-only cable |
| Port not readable/writable | Not in `dialout`, or the udev rule is missing — run `./scripts/heltec-setup.sh setup` |
| `not tagged against ModemManager` | udev rule installed but the board was not replugged |
| `port held by PID(s)` | A serial monitor is still open somewhere |

Do not continue past a failure here — everything downstream will produce confusing results.

## Step 2 — Identify the chip

```bash
./scripts/heltec-dev.sh chip-id
```

Expected: ESP32-S3, 8 MB embedded flash, and a MAC. FTG1's MAC is `44:1B:F6:FB:8E:00` — if the MAC
differs, you are talking to a different board; say so rather than assuming.

If it fails to sync: hold **PRG**, tap **RST**, release **PRG**, retry. Needing that dance every time
is itself a finding — the auto-reset circuit should make it unnecessary.

## Step 3 — Determine what firmware is running

Read the boot banner without reflashing:

```bash
./scripts/heltec-dev.sh raw
```

Tap **RST** and read. Then `Ctrl-C`.

- `==== Heltec WiFi LoRa 32 V3 bring-up ====` → the PlatformIO diagnostic
- Meshtastic boot logs → Meshtastic
- RNode / Reticulum output → RNode

**Report which one, always.** Knowing which firmware is loaded is the single most useful fact for the
next session, and the easiest to get wrong by assumption.

## Step 4 — Radio verification (only if the diagnostic firmware is wanted)

**This reflashes the board and destroys whatever firmware is on it.** Confirm with the user first if
the board is currently running Meshtastic or RNode with configuration worth keeping — export it first
(`meshtastic --export-config`).

```bash
./scripts/heltec-dev.sh flash
```

A healthy board reports:

```
efuse mac : 44:1B:F6:FB:8E:00
  i2c device at 0x3C  (SSD1306 OLED)
  SX1262 up at 915.0 MHz, SF9/BW125/CR4:7
result: OLED ok, radio ok
```

The SX1262 line is the meaningful one. It proves the 1.8 V TCXO reference and the DIO2 RF-switch
setting are both right — the two settings that differ from RadioLib's defaults, and the usual reason
a V3 initialises cleanly and then transmits nothing.

The LED should blink at 1 Hz and holding **PRG** should print to the console. **Ask the user to
confirm those two visually** — they cannot be observed from here, so do not report them as verified.

`VBAT 0.01 V` with no pack attached is correct. The `VBAT_DIVIDER` constant is uncalibrated (#11).

## Step 5 — Report

Host checks, chip identity, **the firmware the board is running**, and radio results if Step 4 ran.

Report only what was observed. If the board was not attached, say the check did not run — never
infer a result.
