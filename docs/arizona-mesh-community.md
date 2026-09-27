# Participating in the Arizona Meshtastic Community

FTG1 follows the Arizona Meshtastic Community's published conventions and feeds
their broker. Their guidance is at
<https://azmsh.net/docs/recommended-settings.html> and in the "Get Started"
channel of their Discord. Credentials and the exact
topic are in `etc/secrets/azmsh-mqtt.conf`, which is gitignored.

## The region split matters, and FTG1 is on the non-obvious side

The community runs **two** different radio configurations:

| Where | Preset | Frequency slot |
|---|---|---|
| Phoenix and Tucson metro areas | Medium-Fast | 18 |
| Everywhere else, including Flagstaff | **Long-Fast** | **20** |

**Do not "upgrade" FTG1 to Medium-Fast / slot 18.** That is the metro setting.
Applying it would take FTG1 off the mesh it can actually hear — the 100-plus
nodes in `docs/meshtastic-rf-survey.md`. Outside the metros the community uses
the Meshtastic defaults, which is what FTG1 already ran.

`lora.channel_num` is **0**, meaning the slot is derived from the channel name
rather than set explicitly. That derivation yields the community's slot 20 for a
default-named LongFast primary in the US region, and FTG1 demonstrably hears the
local mesh, so it was left at 0. **Setting 20 explicitly was considered and
rejected**: if the derived value were ever not 20, writing an explicit 20 would
move the radio to a different frequency and silently cost every peer.

## What was changed on 2026-09-26

All values read back from the device after writing, never trusted from the CLI's
own output.

| Setting | Was | Now | Why |
|---|---|---|---|
| `position.position_broadcast_secs` | 3600 | 43200 | stationary profile |
| `device.node_info_broadcast_secs` | 10800 | 43200 | stationary profile |
| `position.position_broadcast_smart_enabled` | True | False | stationary profile |
| `lora.config_ok_to_mqtt` | False | True | their explicit request |
| `telemetry.device_update_interval` | disabled | 3600 | their profile |
| `neighbor_info.enabled` | False | True | their profile |
| `neighbor_info.update_interval` | 0 | 39600 | stationary, 11 h |
| `neighbor_info.transmit_over_lora` | False | True | their profile |
| `mqtt.root` | `msh/US` | `msh/US/AZ/Flagstaff` | their topic convention |
| `mqtt.map_reporting_enabled` | False | True | feeds their maps |
| `mqtt.map_report_settings.publish_interval_secs` | 0 | 21600 | stationary, 6 h |
| `mqtt.map_report_settings.position_precision` | unset | 32 | matches channel 0 |

Uplink on channel 0 and downlink off everywhere already matched their guidance.

**Why this was worth doing:** FTG1 was emitting 5.8% of all traffic we capture
while being one of 107 senders, where an even share is 0.9%. It was at
Meshtastic defaults, not misconfigured — the community simply asks stationary
nodes to be quieter than the defaults. The change takes FTG1 from about 38
packets a day to roughly 7.

`lora.config_ok_to_mqtt` deserves its own note. It is how a node consents to
its packets being uploaded to MQTT. Ours was `False` while FTG1 uplinked
everyone else's traffic to a broker and a public site, which is a position not
worth defending.

## We bridge, we do not repoint

**A Meshtastic node has exactly one broker.** Its MQTT config is `address`,
`enabled`, `encryptionEnabled`, `password`, `root`, `username` — verified on the
device, and there is no second-broker field anywhere in the configuration.

So setting `mqtt.address` to `mqtt.azmsh.net` would **replace** the local
broker, and meshview ingests from the local broker, so the public site would
stop updating. Instead:

- FTG1 publishes to mosquitto on pi4, unchanged, but now under
  `msh/US/AZ/Flagstaff`, which is already the community's topic.
- An **outbound-only** mosquitto bridge forwards that topic to their broker. The
  config is staged at `~/deployments/prod/etc/azmsh-bridge.conf` on pi4 and
  needs root to install.

Outbound-only is not merely tidy. It makes downlink into the local mesh
structurally impossible rather than a per-channel flag that could be flipped
later, and both the community's guidance and this project's own #7 work identify
downlink onto the primary channel as the thing that must never happen.

Because the radio's root now matches their convention, the bridge needs no topic
rewriting: the same topic on both sides.

meshview subscribes to **both** `msh/US/2/e/#` and `msh/US/AZ/#` during the
changeover, so the cutover cost no ingest. Confirmed on 2026-09-26:
`msh/US/AZ/Flagstaff/2/e/LongFast/!f6fb8e00` arriving, with the old topic silent
after the reboot. The old filter can be dropped once nothing wants it.

## Verifying the community broker, and what cannot be verified

`mqtt.azmsh.net` resolves and **1883 is open while 8883 is not**, so it is plain
MQTT with no TLS, matching their instructions.

The credentials authenticate. The handshake gives `CONNACK (0)` and the
subscription is granted, not refused. But **zero messages are delivered to that
account**, across 80 seconds of sampling — consistent with a published
uplink-only account whose reads are filtered by ACL.

**So our own feed cannot be confirmed from this account.** Confirmation has to
come from their own tools — <https://view.azmsh.net/>,
<https://map.azmsh.net/>, <https://metrics.azmsh.net/> — or from a community
member. Do not read the silence as a fault.
