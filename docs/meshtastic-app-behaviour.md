# The Meshtastic Android app: two behaviours that look like faults

Both of these cost real time, and neither is a fault in the radio or the
firmware. They are properties of the Android app and of Android's Bluetooth
stack, which is why they are collected here rather than with the hardware facts
in `CLAUDE.md`.

## A stale Android bond makes the radio invisible, not just unpairable

Cost real time on 2026-09-01. **Reflashing does not change the board's BLE
address**, so a bond Android made under RNode survives the change to Meshtastic
and Android keeps honouring it.

The symptom misleads: **the phone's scan does not list the device at all**,
because Android excludes bonded devices from discovery. That looks exactly like a
radio not advertising, but there is nothing to fix on the board.

The tell is asymmetry — `meshtastic --ble-scan` from a Linux host finds it at the
same moment. **Desktop sees it, phone does not → stale bond on the phone.** Fix
it in Android's Bluetooth settings: forget the entry, then pair from inside the
app. Power-cycling the radio and rebooting the phone were both tried and neither
helps; the bond is on the phone.

BLE advertises on **MAC + 1** (`…AC:5D` where the WiFi MAC is `…AC:5C`) —
ordinary ESP32 behaviour. Do not read the mismatch as the wrong board.

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

## Why these are here and not in CLAUDE.md

`CLAUDE.md` carries the findings a session needs in its head while touching the
radio. These two matter only when a phone is involved, and FTG1 has run its own
WiFi since 2026-09-23, which disables Bluetooth entirely. They stay written down
because the moment a phone is reintroduced both traps return unchanged.
