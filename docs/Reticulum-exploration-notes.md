# Reticulum / RNode on FTG1 — exploration notes

Working notes for #8. Meshtastic was removed from the board on 2026-08-19 to make
room for this; the two cannot coexist.

## Flashing RNode onto a Heltec V3 works

`rnodeconf --autoinstall` supports this board directly. Menu option **8**
(Heltec LoRa32 v3), then band **3** (915 MHz), which selects model `0xCA` —
850–950 MHz, SX1262, 22 dBm max.

```
Product          : Heltec LoRa32 v3 850 - 950 MHz (c1:ca:3a)
Device signature : Validated - Local signature
Firmware version : 1.86
Device mode      : Normal (host-controlled)
```

Two things worth knowing before repeating it:

- **`--autoinstall` is interactive but scriptable.** `printf '8\n\n3\ny\n'` drives
  it. Answer `n` at "Is the above correct?" first — it prints a full summary of
  board, band and firmware file, so the selection can be checked before anything
  is written.
- **The first interface bring-up fails and then fixes itself.** `Radio state
  mismatch` followed by `[Errno 9] Bad file descriptor`, then a successful
  automatic retry five seconds later. This is the "known friction" #8 refers to.
  Do not chase it.

## RNode is a modem, not a mesh node

There is no NodeDB and no peer list. Meshtastic showed 105 nodes because every
node broadcasts nodeinfo continuously; Reticulum shows only what announces, and
announcing requires someone running Reticulum.

**The local Meshtastic mesh is invisible, by construction.** Those nodes are
still transmitting a few hundred metres away, but they use Meshtastic's sync
word at SF11/BW250 and its own framing. Same hardware filter that makes the
PlatformIO diagnostic deaf.

## Two nodes, and a message that crossed the air

A second Heltec V3 (MAC `44:1B:F6:FA:AC:5C`, `/dev/ttyUSB1`) was flashed with
RNode 1.86 on 2026-08-24 and an LXMF message was delivered from it to FTG1 over
915 MHz.

```
from    : <3cb6d9b9ef87ad8ed5c0df892462b655>   (node B)
to      : <9c001c033d66827d06fefbbbf0737af6>   (FTG1)
title   : RF link test B -> A
content : Sent from the second Heltec over 915 MHz LoRa.
```

**How the test was made honest.** Two independent Reticulum instances, one per
radio. Instance A keeps its three internet backbones; instance B, configured in
`etc/reticulum/config.node-b`, has **only its RNode interface**. B therefore has
no path to anything except over the air, and it learned FTG1's address as *1 hop
away on `RNodeInterface[RNode B]`*.

The interface counters corroborate it rather than relying on that alone — each
radio's transmit total matches the other's receive total exactly:

| | A (`ttyUSB0`) | B (`ttyUSB1`) |
|---|---|---|
| TX | 458 B | 556 B |
| RX | 556 B | 458 B |
| Channel load | 2.36% | 2.08% |

### A phone as the third node

On 2026-08-26 an Android phone running **Sideband 2.0.1**, paired to the second
Heltec over Bluetooth, sent `Hello, world!` to FTG1 over 915 MHz. Phone → BLE →
RNode → LoRa → RNode → laptop, with **no internet anywhere in the chain** and no
computer on the phone's end.

That is the field configuration: the phone is the host, the RNode is the radio,
and together they are a complete node with their own identity and LXMF address.

**The Heltec V3 is BLE-only, not Bluetooth Classic.** The firmware sets
`HAS_BLUETOOTH false` / `HAS_BLE true` for this board, selecting `BLESerial`
rather than `BluetoothSerial`, because the **ESP32-S3 has no Classic radio at
all**. Consequences: Android pairs and bonds it but offers no "connect" action —
tapping it in Bluetooth settings correctly does nothing, since the app opens the
GATT link, not the OS. Android 12+ also gates BLE behind the separate **Nearby
devices** permission.

Three steps in Sideband are each easy to miss, and each fails silently:

1. **`Preferences → Connectivity → Connect via RNode`** is what brings the
   interface up. `Hardware → RNode` only sets frequency, bandwidth, spreading
   factor, coding rate and power. Configuring the hardware and never enabling
   the interface produces a node that transmits *nothing* — not a weak signal,
   not an undecodable one.
2. **Restart the RNS service** after changing Connectivity. Sideband says so on
   that screen and provides the button; the change does not take effect
   otherwise.
3. **The recipient's keys must be known before a message can be composed.** An
   address is a hash of a public key, so the sender needs the key itself to
   encrypt. It arrives in an announce, or is fetched with the app's request-keys
   action. Until then the compose field stays locked.

**Diagnosing from the radio beats guessing at the UI.** Whether a node is
transmitting is answerable from the far end: watch the receiver's RX byte
counter and its path table. Three failure modes are distinguishable there —
nothing on the channel at all (interface not enabled), energy but no decode
(parameter mismatch or front-end overload), or a decode with the address
appearing at 1 hop (working).

**Interference readings do not identify their source.** FTG1 showed −22 to
−26 dBm interference that was assumed to be the phone; powering off an unrelated
local LoRa network stopped it, and the phone turned out to be transmitting
nothing at the time. Check what else is on the band before drawing conclusions
from an interference figure.

### `shared_instance_port` does nothing in RNS 1.x

This cost real time and gives a **silently wrong result**, which is worse than
an error.

RNS shares an instance over an **AF_UNIX socket keyed by `instance_name`**. The
`shared_instance_port` setting is ignored unless `shared_instance_type = tcp` is
also set. Two instances with different ports but no distinct `instance_name`
therefore collapse into one: the second logs

```
Started rnsd ... connected to another shared local instance,
this is probably NOT what you want!
```

and then **both radios belong to the same stack**. Any "link test" run in that
state passes without a single bit crossing the air. Set `instance_name` per
instance, and check `rnstatus` names the right one — B reports
`Shared Instance[rns/rnodeb]`.

### Drop the power for bench work

Both boards run at **2 dBm**, not 22. Inches apart, full power overloads the
receiver front end. Even at minimum, B reports interference at −28 dBm.

## Nobody else is running Reticulum over RF near FTG1

Measured, not assumed: **0 bytes received, 0.0% channel load** over several hours
at 915 MHz / BW 125 kHz / SF8 / CR5, noise floor −92 to −96 dBm. That remains
true of *strangers* — the only traffic on the air is between our own two nodes.

Unlike Meshtastic's LongFast there is **no default channel everyone lands on**.
Two RNodes must agree on frequency, bandwidth, spreading factor and coding rate
in advance. The parameters above are a common convention, not a standard.

## The public testnet is gone — find entry points from the live directories

`amsterdam.connect.reticulum.network` and `dublin.connect.reticulum.network`
have **no DNS records** as of 2026-08-19. Reticulum 1.x replaced the central
testnet with on-network interface discovery. Any guide still listing them is
stale, and that includes most search results.

Live entry points come from `rmap.world`, which serves JSON at `/?json=1`:
606 discovered nodes, 261 with a host and port. `directory.rns.recipes` was
empty when checked. **TCP-test a candidate before putting it in the config** —
seven were tested here and all seven answered.

The three in `etc/reticulum/config` were chosen for operator and network
diversity, not for any special status.

## What the internet side shows

304 destinations learned in about four minutes, hop counts from 2 to 31 with
the bulk at 3–8.

Path entries carry **expiry timestamps a week out**. That is the concrete
difference from Meshtastic: Reticulum caches routes and re-uses them, rather
than flooding every packet and de-duplicating at each hop.

## Deliberate configuration choices

- **`enable_transport = False`.** This instance is a leaf. It does not relay
  other people's traffic and, more importantly, **does not bridge internet
  traffic onto the LoRa radio**. Turning it on makes FTG1 a gateway between the
  global Reticulum network and 915 MHz over Flagstaff — a decision to take
  deliberately, not by default.
- **`discoverable = No` on every interface.** The discovery system is what
  populates community maps, and its announcement fields include latitude,
  longitude and height. Off is consistent with how position is handled on the
  Meshtastic side.

## FTG1's identity and LXMF address

| | |
|---|---|
| Identity hash | `<093df62a1a0b828fd38bf9d2013b4394>` |
| LXMF address | `<9c001c033d66827d06fefbbbf0737af6>` |
| Display name | `FTG1` |
| Private key | `etc/secrets/ftg1.identity` — **gitignored, 64 bytes, no recovery if lost** |

Generated with `rnid -g`, and `lxmd` runs on it from `etc/lxmf/config`.

Unlike the Meshtastic node ID, **this is not derived from the MAC**. It is a
keypair on disk. Lose `etc/secrets/ftg1.identity` and the address is gone
permanently — there is no authority to re-issue it, which is the same property
that makes the address self-authenticating.

**`lxmd --identity <path>` does not do what it looks like.** That flag is for
authenticating queries to a remote node. On first run `lxmd` created its own
primary identity in the config directory and announced a different address; the
fix is to place the intended key at `<config>/identity` before starting it, and
to delete the ratchets belonging to the discarded identity.

`etc/lxmf/identity` and `etc/lxmf/storage/` are gitignored — private key and
live crypto state. Only `etc/lxmf/config` is tracked.

Announcing put **450 bytes out over the LoRa interface** and roughly 660 bytes
out each internet interface, so FTG1 now transmits on 915 MHz periodically even
though nothing is listening on RF.

**The propagation node stays off** (`enable_node = no`). Running one means
storing and forwarding other people's mail; that is the interesting capability,
but it is a commitment to make deliberately.

## Delivery proven end to end

A loopback LXMessage was sent to `<9c001c033d66827d06fefbbbf0737af6>` and
arrived: sender got a delivery confirmation, `lxmd` wrote the message under
`etc/lxmf/storage/messages/`, and `etc/lxmf/on-inbound.sh` fired.

Two things learned doing it:

- **`lxmd -i <path>` is silently ignored when a config file exists.** `lxmd.py`
  sets `on_inbound` from `[lxmf] on_inbound` in the config, and falls back to
  `None` otherwise — overwriting whatever the command line supplied. Put it in
  the config file.
- **The received message reported `signature NOT VALIDATED`.** That is correct
  behaviour, not a fault: the test sender used a throwaway identity that was
  never announced, so the receiver had no public key to verify against.
  Encryption and delivery are independent of authorship verification here.

## Battery reading is wrong here too

`rnstatus` reports a battery percentage and "discharging" on a board with no
pack fitted. Same floating charger rail described in `CLAUDE.md` — three
firmwares now (diagnostic, Meshtastic, RNode) have all been fooled by it. It is
a hardware property, not a firmware bug.

## Getting back to Meshtastic

`etc/firmware/rollback-heltec-v3/device-install.sh` with the 2.7.26.54e0d8d
factory image, then re-import from `etc/secrets/`. The node ID `!f6fb8e00` is
derived from the MAC and survives any reflash.
