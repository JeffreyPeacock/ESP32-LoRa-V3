# Reaching a node over WiFi, and what WiFi costs

Only relevant when a node is running its own WiFi. FTG1 does not today: it
keeps Bluetooth for a phone and reaches MQTT through a proxy over the serial
cable instead. See `CLAUDE.md` for why those two cannot both be on.


WiFi and BLE are mutually exclusive on ESP32, so a node using its own WiFi is
unreachable over Bluetooth. It is not unreachable in general — it serves three
interfaces on the LAN:

| Port | What | Use |
|---|---|---|
| 4403 | Meshtastic API | **Add as a "network device" in the phone app** — full messaging |
| 80/443 | built-in web UI | browser |
| — | — | `meshtastic --host <ip>` instead of `--port /dev/ttyUSB0` |

The app's "add a network device" feature expects a **radio** on 4403. Pointing
it at an MQTT broker on 1883 makes it send Meshtastic stream framing to the
broker, which logs `Invalid remaining length bytes:0x94949494` — `0x94` is the
Meshtastic start byte. That is a wrong-address symptom, not a broker fault.

The node's address comes from DHCP, so set a reservation on the router before
depending on it.

### WiFi failure codes worth recognising

`Reason: 15 - 4WAY_HANDSHAKE_TIMEOUT`, looping every ~8 s, means the **PSK is
wrong** — the node found the AP and failed authentication. It is not a band or
SSID problem. Read it with a raw serial capture; the protobuf API hides these
logs. Note the ESP32-S3 is **2.4 GHz only**, so also confirm the SSID exists on
2.4 GHz.

