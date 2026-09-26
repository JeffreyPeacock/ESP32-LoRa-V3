# Configuring a Meshtastic node to report into meshview

This is FTG1's gateway configuration, written so it can be reproduced on any
Meshtastic node feeding any host. **Everything here is on the radio.** The host
side is reduced to the three things it has to provide, near the end; how this
project happens to run them on one particular Pi is in
[`raspberry-pi-deployment.md`](raspberry-pi-deployment.md) and is deliberately
not repeated here, because none of it is required.

## What a gateway does, before you enable one

A Meshtastic MQTT gateway **republishes the packets it receives**, not only the
ones it sends. With `rebroadcastMode: ALL` — the default — a node relays packets
on channels it cannot decrypt, so enabling uplink on the primary channel
publishes **the local mesh's traffic**, not just yours. Everyone within radio
range is uplinked by your node. Decide that is acceptable before switching it
on;
it is the whole point of a public meshview site, and it is also not reversible
for packets already sent.

Uplink (mesh to broker) is all that reporting needs. Downlink (broker to mesh)
is
a separate switch, is not needed here, and should stay off: on the primary
channel it would rebroadcast public-internet traffic onto the shared local mesh.

## Prerequisites on the radio

- Meshtastic firmware flashed. On `heltec-v3` do not use the vendor
  `device-install.sh`; see [`flashing-meshtastic.md`](flashing-meshtastic.md).
- `lora.region` set. Without a region the radio will not transmit at all.
- An owner name, long and short.

**The node ID is derived from the MAC**, not configured. It survives reflashing
and factory reset, and it becomes the last element of the MQTT topic, so it is
public and permanent. Choose the short name with that in mind.

## Choose how the radio reaches the broker

| Transport | Uplink | Downlink |
|---|---|---|
| The node's own WiFi | works | works |
| A phone proxy over BLE | works | **fails** |

WiFi and Bluetooth cannot both run on an ESP32, so enabling WiFi means **no
phone
can pair with the radio at all**. For a permanently hosted gateway that is the
right trade, and it is what FTG1 does. The serial or BLE proxy exists only for a
node that must keep Bluetooth; it is described, and retired, in
[`mqtt-over-serial-proxy.md`](mqtt-over-serial-proxy.md).

## The settings

**The CLI prints every value it sets**, including PSKs and passwords. Do not
paste the output of these commands anywhere. Substitute your own values.

```bash
meshtastic --host <radio> \
  --set network.wifi_enabled true \
  --set network.wifi_ssid '<ssid>' \
  --set network.wifi_psk '<psk>'
```

```bash
meshtastic --host <radio> \
  --set mqtt.enabled true \
  --set mqtt.address '<broker host or address>' \
  --set mqtt.username '<user>' \
  --set mqtt.password '<pass>' \
  --set mqtt.root 'msh/US' \
  --set mqtt.encryption_enabled true \
  --set mqtt.tls_enabled false \
  --set mqtt.json_enabled false \
  --set mqtt.map_reporting_enabled false
```

Why each of the last five is set that way:

- **`root`** forms the topic and defaults to `msh/US`. Change it only if your
  broker separates meshes by prefix.
- **`encryption_enabled true`** leaves payloads encrypted between radios; the
  broker relays ciphertext and meshview decrypts with the channel key you give
  it. Turning it off publishes plaintext to anyone reading the broker.
- **`tls_enabled false`** is correct for a broker on your own network. Note that
  `mqtt.meshtastic.org` uses TLS on 8883 **regardless of this flag**, so it is
  not the flag that decides it.
- **`json_enabled false`.** JSON publishing exists for injecting messages from
  the broker side. It emits cleartext, and a reporting gateway does not need it.
- **`map_reporting_enabled false`.** This is a separate feature that reports
your
  node and position to Meshtastic's own public map. It is not how meshview gets
  data, and it is its own privacy decision.

Then enable uplink, which is **per channel and off by default** — a radio will
otherwise connect to the broker and publish nothing:

```bash
meshtastic --host <radio> --ch-index 0 --ch-set uplink_enabled true
meshtastic --host <radio> --ch-index 0 --ch-set downlink_enabled false
```

Then reboot. **The firmware starts its MQTT module at boot**, so a radio
configured while running publishes nothing and reports no error:

```bash
meshtastic --host <radio> --reboot
```

FTG1's own values, read from the device on 2026-09-25:

| | |
|---|---|
| `mqtt.enabled` | `True` |
| `mqtt.root` | `msh/US` |
| `mqtt.encryption_enabled` | `True` |
| `mqtt.tls_enabled` | `False` |
| `mqtt.json_enabled` | `False` |
| `mqtt.map_reporting_enabled` | `False` |
| `mqtt.proxy_to_client_enabled` | `False` |
| `network.wifi_enabled` | `True` |
| Channel 0 | uplink on, downlink off, `positionPrecision: 32` |
| Channels 1 and 2 | uplink off, downlink off |
| `position.fixed_position` | `True` |
| `lora.hop_limit` | `3` (default, maximum 7) |
| `device.rebroadcast_mode` | `0` (ALL) |

## Position

A node with no GPS needs a fixed position, or it appears on no map. How much of
it to publish is a per-channel setting, `position_precision`, and the reasoning
plus the arithmetic is in
[`ftg1-position-and-privacy.md`](ftg1-position-and-privacy.md). Read that before
choosing a value: reduced precision publishes an **area**, and an offset
coordinate is a different mechanism with different consequences.

## Verify in three places, because each can lie separately

**On the radio.** A successful `--set` is not evidence the device took the
value:
`position.position_broadcast_secs 60` printed success, exited 0, and the device
still reported 3600. Read every setting back. The flat keys come from `--get`.
Channel flags and `positionPrecision` are **not** in `--export-config`, which
encodes channels inside `channel_url`, so those need `--info`.

> `--info` prints the **entire NodeDB** and every channel PSK. Grep it for
> specific keys. Grepping it for `latitude` returns every peer's coordinates,
> which is someone else's location, not yours.

**At the broker.** The topic shape is
`<root>/<region>/2/e/<channel>/<gateway>`, which for FTG1 is
`msh/US/2/e/LongFast/!f6fb8e00`. Two traps here produce identical empty output:
`mosquitto_sub` block-buffers when its stdout is a pipe, so under `timeout` it
is
killed before it flushes and prints **nothing at all**; and the mesh may simply
be quiet, measured here at one packet every ~140 s. Redirect to a file or use
`stdbuf -oL`, and never conclude anything from a silent sample. A comparison
that
can fail — old and new filter running at the same time, counts compared — is
worth more than any single watch.

**In meshview.** The gateway gets a row in the `node` table with
`is_mqtt_gateway` set, and its `node_id` is the integer form of the hex id.

## What the host has to provide

Three things, stated as an interface so any host satisfies them:

1. **A broker the radio can reach**, with the credentials configured above.
2. **meshview subscribed to a filter that covers your gateway.**
   `<root>/<region>/2/e/#` is the useful level. Do not pin the channel name or
   the gateway id: those are the two elements that can legitimately change, and
   pinning them drops traffic with no error.
3. **One writer to meshview's SQLite database.** Stop the ingest process before
   running anything else that writes to it.

## Three behaviours that look like faults and are not

- **Nodes appear as ids before they appear as names.** meshview learns a name
  only from a NodeInfo packet, sent every 10800 s (3 hours) by default, so the
  map fills over days rather than minutes.
- **Several nodes reporting one identical coordinate is quantisation, not a
  bug.** A sender running reduced precision publishes the corner of a grid cell.
  Do not correct it in the database; the next packet overwrites the edit. The
  only fix is at that radio.
- **Backfilling the node table from another source can grow the database and
  leave the map unchanged**, if the map filters on an activity window and the
  backfilled rows carry their original timestamps. That is correct behaviour:
  a node last heard weeks ago should not claim to be current.
