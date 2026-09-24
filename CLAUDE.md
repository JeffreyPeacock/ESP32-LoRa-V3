# Project instructions

Working notes for this repository. These are facts that were expensive to
establish and are easy to get wrong from memory or from generic documentation.

## What this project is

A Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262), **FTG1**, intended to exchange
text messages with radios at **SJC** and **SNA**, hundreds of km away. Sites are
named by the nearest airport ident.

Two constraints shape everything. **Only FTG1 is ours**, so prefer work that can
be completed and verified solo. And **a backbone is required between sites**:
Meshtastic caps the hop limit at 7 and each hop is a few km, so the 900 km gap
cannot be closed with more LoRa hops. Meshtastic bridges meshes with MQTT, which
needs IP reachability between gateways; what carries that IP is a free choice.

**Current direction:** Meshtastic. Since 2026-09-22 FTG1 also feeds a public
meshview site from pi4. Reticulum is the likely long-term end state, because it
routes rather than floods and holds messages for offline nodes, but it is paused.

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

### The two LEDs mean completely different things

**Orange = charger, hardware. White = firmware, GPIO35.** Confusing them wastes
time, because only one of them says anything about software.

The **orange** LED is driven by the **TP4054** lithium charger's open-drain
`CHRG` pin through a 330 Ω resistor. No GPIO is involved and the ESP32 cannot
affect it. It lights while charging and **goes out when the cycle terminates** —
so orange-then-dark over a few hours is a completed charge, not a fault. The
schematic names the colour explicitly; the reference designator is probably
`LED2` but the drawing extracts poorly to text, so trust the colour, not the
number.

**A steady LED is never the firmware.** RNode animates the white LED and nothing
else: standby breathes, not-ready breathes faster, error flashes. Its only
steady state is `led_indicate_console`, which is NeoPixel-only and the V3 has no
NeoPixel — both RX and TX map to `pin_led_rx = 35`. So a constant light on this
board is the charger talking.

**The charger restarts on any VBUS interruption.** Observed 2026-08-27: the
orange LED lit when an unrelated USB device was plugged into the same powered
hub. The board is bus-powered and was three hubs deep sharing a rail with ten
storage devices; a momentary dip drops it to battery, and when USB returns the
TP4054 begins a fresh cycle to top up. The trigger was not conclusively
identified — do not read a diagnosis into the LED beyond "a charge cycle is
running".

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

**`position_precision` on channel 0 was 13 until 2026-09-23 and is now 32.** The
old note here said the published position was quantised to roughly km scale. That
is no longer true: the radio now transmits the stored coordinate exactly, to every
map and every node that hears it.

Only one thing blunts the disclosure now, and it is the one that always did the
real work: **the stored fix is a public landmark, not the operator's address.**
Precision was blurring a decoy, which bought nothing and cost accuracy, so the
owner chose to give it up.

Note the ordering consequence: once a position is broadcast, a location-hinting
**node name adds little further disclosure** — the position packet is more
precise than the name. The name decision was made under the older assumption that
no position was being sent.

### Reduced precision is a shared bucket, not a location

**Eight nodes reported the identical latitude `352059392`**, including FTG2 and
six strangers. A coordinate several nodes share is a quantisation cell, not a
place. This is what made FTG1 appear 1.4 km from its true position and land on
exactly the spot FTG2 had occupied — they were rounded into the same bucket
rather than being in the same field.

Two consequences worth keeping. **Do not read a position on a map as a
measurement** when the sender runs reduced precision. And **fixing it in the
database does not work**: meshview stores whatever arrives, so a hand-edited row
is overwritten by the next position packet. The only fix is at the radio.

## There is an active mesh in range of FTG1 (#3)

**FTG1 is not isolated.** 155 peers in the pi4 ledger as of 2026-09-23, 89 with
positions, 19 within 15 mi, typical SNR −5 to −6 dB. Real RF peers exist to test
against, so link behaviour never had to wait on SJC. The peer table, traceroutes
and terrain arithmetic are in `docs/meshtastic-rf-survey.md`.

Three conclusions generalise:

- **The path off the Flagstaff bowl is two routers, not one.** `Eldn`
  (`!085e15cb`) does not see Prescott; it spans 103.7 km SW to `!1fa06b14`, which
  does. An earlier session credited one node with the whole reach and was wrong.
- **`hopsAway: 0` says nothing about line of sight on this terrain.** That link is
  0-hop at ~0 dB SNR through a summit standing 384 m above the line of sight,
  twenty times the first Fresnel radius. Do not infer geometry from hop counts.
- **Routing is asymmetric**, which is normal. Remember it when a one-way test
  looks like a failure.

**Do not commit other operators' positions.** Node IDs are already public;
coordinates are someone else's location.

### Peer positions are not committed

`docs/peers.local.md` is excluded by `docs/*.local.*`. **The NodeDB ages entries
out, so a scan is not a record** — `peers-report.sh` accumulates everything ever
seen into `docs/peers.local.json` and merges it back each run. It refuses to run
unless both are gitignored. There are now two ledgers, one per host; **the pi4
one is authoritative** because the radio is there.

**Local secrets live in `etc/secrets/`**, ignored as a whole directory. Device
config exports carry channel PSKs, the WiFi PSK and `security.privateKey`.

## Normal operating mode is BLE, no network

That was the rule while a phone was the host. **FTG1 changed on 2026-09-23 and
now runs its own WiFi**, so its Bluetooth is off and it reaches the MQTT broker
directly. Ordinary Meshtastic use still needs no internet — the mesh found in #3
runs entirely over RF — but this node is no longer an ordinary case.

**As of 2026-09-22 FTG1 lives on pi4, not on mahtoh.** The board was physically
moved. It is USB-attached to pi4, held by a serial process there, with Bluetooth
still enabled for a phone. **FTG2 is gone**, lost and presumed destroyed, and has
been removed from the radio's node database, from the peer ledger and from
meshview.

**The listener on mahtoh is stopped and disabled.** It was still enabled against
`…usb-0:3:1.0-port0`, a path with no radio behind it since 12:54 on 2026-09-22.
It logged a disconnect and could not work. Re-point its `[listen] port` before
re-enabling it anywhere.

**The serial port serves one process at a time.** Whatever holds it — the
listener, the MQTT proxy — blocks `meshtastic --port`, and the symptom is a
silent non-response rather than an error. Stop the holder first.

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

The full injection recipe, with the verified serial log, is in
`docs/mqtt-broker-vps.md`.


Keep `downlink_enabled` **off** on the primary channel. Downlink there would
rebroadcast public-internet traffic onto the shared local mesh. It belongs only
on the dedicated `mqtt` channel.

Broker gotchas that cost real time — amqtt's protocol version and its
anonymous-auth trap, mosquitto's localhost default — are in
`docs/mqtt-broker-vps.md`.

## The diagnostic firmware is deaf to the mesh

`src/main.cpp` uses the private sync word at SF9/BW125; Meshtastic uses a
different sync word at SF11/BW250. **The SX1262 raises a receive interrupt only
for a matching sync word and modulation**, so the diagnostic firmware cannot
hear a single mesh packet. That is correct behaviour, not a broken radio.

The same mechanism explains what a node repeats. **What it can hear is a
hardware filter** — sync word, SF, BW, CR, frequency — so LoRaWAN is rejected in
the modem before firmware sees a byte. **What it forwards is firmware** — hop
limit, dedup, `rebroadcastMode`. With `rebroadcastMode: ALL` a node relays
packets on channels it **cannot decrypt**, which is how a shared LongFast
carrier serves everyone's private channels, and why strangers' radios carry our
traffic. Repeating is not a property of the radio: our `CLIENT` node already
relays for others, and `ROUTER` mainly means well-sited infrastructure.

### Sync words in use here

Read from each project's source, not assumed. On SX126x the sync word is a
16-bit register pair; on SX127x it is one byte, and the two columns below are
the same value expressed either way.

| Stack | SX127x | SX126x | Note |
|---|---|---|---|
| **RNode / Reticulum** | `0x12` | `0x1424` | the conventional **private** value |
| Our PlatformIO diagnostic | — | `0x1424` | `RADIOLIB_SX126X_SYNC_WORD_PRIVATE` |
| Meshtastic | `0x2b` | `0x24B4` | `RadioLibInterface.h` |
| LoRaWAN | `0x34` | `0x3444` | the **public** value |

**RNode does not use a custom sync word** — it uses the ordinary private one
that most non-LoRaWAN devices default to. And it cannot be changed: the setter
ignores its argument and hardcodes the value, with a `TODO` in the source asking
why.

```c
void sx126x::setSyncWord(uint16_t sw) {
  // TODO: Why was this hardcoded instead of using the config value?
  writeRegister(REG_SYNC_WORD_MSB_6X, 0x14);
  writeRegister(REG_SYNC_WORD_LSB_6X, 0x24);
}
```

Two consequences:

- **Meshtastic and RNode cannot collide.** `0x24B4` differs from `0x1424` in
  both bytes, so the separation is real rather than incidental.
- **Our diagnostic firmware shares RNode's sync word.** Only the modulation
  differs today — SF9/BW125/CR4:7 against RNode's SF8/BW125/CR5. A RadioLib
  sketch matching both would be *heard* by an RNode, though nothing would decode
  as a packet because the framing above the PHY is different. **A sync word is
  not isolation.** It stops decoding; it does not stop the energy, and CSMA
  still defers to it.

## A stale Android bond makes the radio invisible, not just unpairable

Cost real time on 2026-09-01. **Reflashing the board does not change its BLE
address**, so a pairing Android made when the board ran RNode survives the
change to Meshtastic — and Android keeps honouring it.

The symptom is misleading: **the phone's scan does not list the device at all.**
Android excludes already-bonded devices from discovery results, so it looks
exactly like a radio that is not advertising. It is not a firmware fault and
there is nothing to fix on the board.

The tell is the asymmetry. Scan from a Linux host at the same moment and the
device is plainly there:

```bash
meshtastic --ble-scan
# Found: name='FTG2_ac5c' address='44:1B:F6:FA:AC:5D'
```

**Desktop sees it, phone does not → stale bond on the phone.** Fix it in
Android's Bluetooth settings: forget the old entry, then pair from inside the
Meshtastic app.

Two things that do **not** help, both tried: power-cycling the radio, and
rebooting the phone. The bond is on the phone and survives both.

Note the address: BLE advertises on **MAC + 1** — `…AC:5D` where the WiFi MAC is
`…AC:5C`. That is ordinary ESP32 behaviour, the peripherals get consecutive
addresses. Do not read the mismatch as the wrong board.

## A channel is not a direct message, and the app hides the difference

Cost a wrong turn on 2026-09-02. In the Meshtastic app a conversation is keyed
`ContactKey("$channel$destination")`, so what looks like one list is two kinds
of thing:

| Shown as | Key | Goes to |
|---|---|---|
| LongFast | `0^all` | everyone in range |
| mqtt | `1^all` | everyone in range |
| ftg-priv | `2^all` | everyone holding that key |
| **FTG1** | `8!f6fb8e00` | **that node only** |

`8` is `PKC_CHANNEL_INDEX`, a sentinel for public-key encryption — the radio has
no channel 8. The app's own test is
`isDirectMessage = channel == null || channel == PKC_CHANNEL_INDEX`.

**Picking a channel sends a broadcast, however private the channel is.**
`ftg-priv` keeps strangers from reading it, but it is still addressed to `^all`,
so the listener running `dm_only = true` records it and does not forward it. To
reach one node, select the *node* from the contact list, not a channel.

**The app connects to one radio at a time.** It stores a single `deviceAddress`
and `setDeviceAddress` replaces it. It does not forget the others — the picker
is built from Android's bonded devices filtered to Meshtastic names — so
switching is choosing a different entry, not re-pairing.

## MQTT without WiFi, if Bluetooth must stay on

**WiFi and BLE cannot both run on this chip.** `mqtt.proxy_to_client_enabled`
makes the radio hand its MQTT traffic to whatever client holds a link, so a
process on the host can carry it while a phone stays paired over Bluetooth.
Retired on 2026-09-23 when FTG1 moved to its own WiFi. Full write-up, including
the working proxy and the uplink-only reasoning, in
`docs/mqtt-over-serial-proxy.md`.

**The radio must be rebooted after MQTT is enabled**, whichever transport it
uses. The firmware starts its MQTT module at boot; configured while running, it
publishes nothing and reports no error. **Uplink is per channel and off by
default**, so a radio can connect to a broker and republish nothing.

## A successful `--set` is not evidence the device took the value

`meshtastic --set position.position_broadcast_secs 60` printed
`Set position.position_broadcast_secs to 60` and `Writing position configuration
to device`, exited 0, and the device still reported **3600**. The firmware
clamped or ignored it and said nothing.

**Read the setting back after every write.** `--info` is the only check that
means anything; the CLI's own output reports intent, not outcome. The same run
set `position_precision` successfully, so this is per-field rather than a broken
connection.

There is **no flag that sends a position on demand**. Re-applying the fixed
position with `--setlat/--setlon/--setalt` makes the radio transmit one
immediately, which is the way to test a position change without waiting out
`position_broadcast_secs`.

## The Meshtastic CLI echoes every value it sets

`meshtastic --set mqtt.password X` prints `Set mqtt.password to X`. A broker
credential reached a session log this way on 2026-09-22 even though a mask
pattern for `mqtt.password` already existed: it expected `mqtt.password <value>`
and masked the word `to` instead. `scripts/export-transcript.sh` now matches the
CLI's actual wording for any key ending in `password`, `psk`, `private_key` or
`wifi_psk`. **Never print the output of `--set` without masking it.**

The same applies to `--info`, which prints channel PSKs as `"psk": "<base64>"`.

## Reaching a node over WiFi

Only relevant when a node runs its own WiFi, which FTG1 does not. WiFi and BLE
are mutually exclusive on ESP32. The ports, the phone's network-device path and
the WiFi failure codes are in `docs/wifi-and-headless-access.md`.

## Which firmware is on the board

One firmware at a time, and no way to tell from outside. Check before assuming:

```bash
./scripts/heltec-dev.sh raw     # tap RST, read the banner, Ctrl-C
```

`==== Heltec WiFi LoRa 32 V3 bring-up ====` is the PlatformIO diagnostic;
Meshtastic and RNode announce themselves in their own boot logs.
**`heltec-dev.sh flash` overwrites whatever is there**, so run
`meshtastic --export-config` first if the configuration matters.

**Do not use Meshtastic's own `device-install.sh` on this board.** Version 2.7.26
reads the real spiffs offset out of the `.mt.json` metadata and then flashes
littlefs to a hardcoded `0x300000` anyway. On the heltec-v3 8MB scheme spiffs is
at `0x670000`, and `0x300000` is inside `app1`, so the script erases the OTA
image it wrote seconds earlier. The board still boots, which is why this is easy
to miss. The by-hand procedure is in `docs/flashing-meshtastic.md`.

FTG1 runs Meshtastic **2.7.26.54e0d8d**, target `heltec-v3`.

## A direct message needs the recipient's public key, or it never transmits

Proven on the bench 2026-09-01. **Broadcasts work immediately; direct messages
do not.** Sending a DM to a node whose public key the sender lacks fails
*locally* — the packet never goes on air:

```
$ meshtastic --dest '!f6fb8e00' --sendtext "..." --ack
Received a NAK, error reason: PKI_SEND_FAIL_PUBLIC_KEY
```

The same NAK appears on the primary channel and on a private one, so it is not a
channel-key problem: **2.7 does not fall back to channel-PSK encryption for a
DM.** Confirmed from the receiving side too, where `--listen` showed a control
broadcast arriving and no trace of the DM.

The key travels in **NodeInfo**. A node that has heard only a text packet knows
the sender's node *number* but not its name or key, so it can be one hop away,
plainly audible, and still unmessagable. NodeInfo goes out on
`device.nodeInfoBroadcastSecs`, **default 10800 s (3 hours)**, so two nodes
flashed together may not be able to message each other for hours. Once exchanged
the DM works first time and is acknowledged.

**A PKI direct message travels on the primary channel regardless of
`--ch-index`.** Sent with `--ch-index 2`, it arrived as `channel: 0`,
`pki_encrypted: True`. Do not read that as a misconfiguration.

`--set-owner` with the values it already holds writes nothing and broadcasts
nothing, so it is not a shortcut for forcing NodeInfo out.

### After an esptool command the board may not answer Meshtastic

Seen 2026-09-04. `heltec-dev.sh chip-id` runs esptool's **stub flasher**, and
although it prints `Hard resetting via RTS pin` the board can be left in a state
where `meshtastic --info` only times out. Waiting does not fix it. An explicit
stubless reset does:

```bash
esptool --port <port> --after hard-reset --no-stub read-mac
```

Then give it ~20 s before talking to it. Read the MAC that way when the board is
already running application firmware — it identifies the board without the stub.

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
USB hwid, so autodetect finds no match and falls back to the first serial port on
the system. `platformio.ini` pins `/dev/ttyUSB*` for this reason.

**ModemManager probes every new tty with AT commands** and collides with esptool
for several seconds after plug-in. `scripts/heltec-setup.sh` installs a udev rule
tagging the device `ID_MM_DEVICE_IGNORE`. That tag is the load-bearing part; the
`MODE`/`GROUP` lines are redundant with Ubuntu's defaults.

**Identify a board by MAC, never by port number or by serial.** Heltec ships
these CP2102Ns with the factory serial `0001`, so `/dev/heltec-0001` and
`/dev/serial/by-id/` collapse every board onto one name and silently resolve to
whichever won the race — observed pointing at the wrong board while the other was
in use. FTG1 is `44:1B:F6:FB:8E:00`. Confirm with
`esptool --port <dev> chip-id`, and treat a board that suddenly answers
differently as a different board until the MAC says otherwise. On 2026-08-23
`/dev/ttyUSB1` was a CP2102N with a unique serial; the next day it was a Heltec
with serial `0001`, and nothing announced the swap.

**Address the board by physical USB socket**, `/dev/serial/by-path/`. FTG1 is on
pi4 at `platform-fd500000.pcie-pci-0000:01:00.0-usb-0:1.3:1.0-port0`, confirmed
by MAC on 2026-09-22. **by-path is preferred over by-id even with one board
attached**, because by-id fails silently and a by-path that stops existing fails
loudly.

**A by-path name is the socket, not the board, so moving a board breaks it.**
FTG1 moved sockets twice: on 2026-09-01 within mahtoh, and on 2026-09-22 to pi4.
The first time `etc/reticulum/config` still named the old path, so `rnsd` would
have failed to open the radio. Re-read the path with `heltec-dev.sh ports` and
re-confirm the MAC after any replug. Other radios on `/dev/ttyACM*` and a CH340
gateway can renumber `ttyUSBn`; the pinned paths are immune, a bare
`/dev/ttyUSB0` is not.

## Three radios now, and only one can run RNode

| Device | Board | MCU | Radio | RNode? |
|---|---|---|---|---|
| on **pi4** | Heltec V3 (FTG1) | ESP32-S3 | SX1262 | capable; runs Meshtastic |
| ~~Heltec V3 #2 (FTG2)~~ | **lost, presumed destroyed 2026-09-22** | — | — | — |
| `ttyACM0` | SparkFun Pro RF | **SAMD21** | RFM95 (SX1276) | **no** |
| `ttyACM1` | SparkFun Pro RF | **SAMD21** | RFM95 (SX1276) | **no** |

**RNode firmware has no SAMD support of any kind** — `rnodeconf` targets AVR,
ESP32 and nRF52, and contains zero references to SAMD. The two Pro RF boards
cannot be RNodes and no amount of configuration changes that. They are a matched
pair for plain point-to-point LoRa with RadioLib, which does interoperate with
an SX1262 as long as frequency, bandwidth, spreading factor, coding rate, sync
word, preamble and CRC all match.

The Pro RF boards use the SAMD21's **native USB**, so they appear as
`/dev/ttyACM*` rather than `/dev/ttyUSB*`, and they disappear from `/dev`
briefly when they reset. A vanished `ttyACM` is usually a reset, not a fault.

## Toolchain layout

Three environments with distinct jobs: the project virtualenv holding the
Meshtastic CLI and esptool, PlatformIO's own data directory, and `pio` on PATH
outside both so every embedded project shares one install. **Code that checks
for the build toolchain must look for `pio` on PATH, not inside the venv.**
`resolve_venv_bin()` accepts four layouts, so **pyenv is this machine's choice
and not a project requirement** — do not reintroduce a hard-coded
`~/.pyenv/versions/...` path. Details in README, "Three environments".

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
documented in `../../Sparkfun/ESP32-LoRa-1Ch-Gateway`, not here.

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
