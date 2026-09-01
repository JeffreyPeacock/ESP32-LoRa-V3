# Restoring the RNode setup

Saved 2026-09-01, immediately before both Heltecs were reflashed with
Meshtastic. Everything needed to rebuild the Reticulum side is here or in
`etc/reticulum/`; nothing was left only on the boards.

## What actually lives on a board, and what does not

Only two things are stored on the Heltec itself:

- the **RNode firmware** (1.86), and
- an **EEPROM provisioning block** — product code, hardware revision, frequency
  range, max TX power, and a device signature.

`ftg1-rnode-info.txt` is that block, read off FTG1 before the reflash.

**The radio parameters are not on the board.** The device reported `Device mode
: Normal (host-controlled)`, which means frequency, bandwidth, spreading factor,
coding rate and TX power are pushed by Reticulum at startup and live in
`~/.reticulum/config`. That file is mirrored in `etc/reticulum/config`, so
reflashing loses none of it.

Identities are also off-board and already saved: `etc/secrets/ftg1.identity`
(Reticulum) and `etc/lxmf/identity` (LXMF). **The LXMF address survives a
reflash** — it is derived from the identity file, not from the radio.

## Parameters both boards ran

| | FTG1 (A) | Heltec #2 (B) |
|---|---|---|
| Frequency | 915.000 MHz | 915.000 MHz |
| Bandwidth | 125 kHz | 125 kHz |
| Spreading factor | 8 | 8 |
| Coding rate | 5 | 5 |
| TX power | **2 dBm** | **2 dBm** |

`txpower = 2` is a bench setting from when the boards sat inches apart. **Raise
it to 17–22 before deploying anything.** It is the single most likely reason a
restored link looks broken.

## To restore

1. Re-provision the board with RNode firmware. It signs locally, which is what
   `Device signature: Validated - Local signature` above records, so this works
   without vendor keys:

   ```bash
   rnodeconf --autoinstall /dev/serial/by-path/<socket>
   ```

   Answer `Heltec LoRa32 v3` and the 850–950 MHz band when prompted, matching
   the product string in `ftg1-rnode-info.txt`.

2. Put the configs back:

   ```bash
   cp etc/reticulum/config        ~/.reticulum/config
   cp etc/reticulum/config.node-b ~/.reticulum-b/config
   cp etc/secrets/ftg1.identity   ~/.reticulum/storage/identity
   ```

3. **Re-confirm the serial path.** A by-path name is the USB socket, not the
   board — it changes whenever a board is moved. Read it with
   `./scripts/heltec-dev.sh ports` and confirm the MAC with `chip-id`, then edit
   the `port =` line. FTG1 is MAC `44:1B:F6:FB:8E:00`; #2 is `44:1B:F6:FA:AC:5C`.

4. Start it and check the interface actually came up, not just that `rnsd` did:

   ```bash
   rnsd &
   rnstatus
   ```
