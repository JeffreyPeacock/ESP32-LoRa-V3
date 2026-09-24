# MQTT over the serial cable, without WiFi

**Retired on 2026-09-23.** FTG1 runs its own WiFi now and publishes to the
broker directly, so nothing uses this. Kept because it is the only way to have
MQTT and Bluetooth at the same time on this chip, and the next radio that must
keep a phone paired will need it.


**WiFi and BLE cannot both run on this chip**, so enabling the radio's own WiFi
to reach an MQTT broker costs the phone its Bluetooth link. There is a third way
that needs neither.

`mqtt.proxy_to_client_enabled` makes the radio hand its MQTT traffic to whatever
client holds a link, and that client talks to the broker. The Python library
implements both directions: `sendMqttClientProxyMessage` outbound and the
`meshtastic.mqttclientproxymessage` pubsub topic inbound. Serial and BLE coexist,
so a process on the host can carry MQTT while a phone stays paired.

Written as `~/bin/meshview-mqtt-proxy.py` on pi4, uplink only, because forwarding
the other way would rebroadcast internet traffic onto a shared RF channel.
**Retired on 2026-09-23** when FTG1 moved to its own WiFi and began publishing
directly. Kept documented because it is the only way to have MQTT and Bluetooth
at once, and because it frees nothing else: with the proxy gone the serial port is
free for `peers-report.sh`, the CLI and esptool.

**The radio must be rebooted after enabling MQTT.** The firmware starts its MQTT
module at boot. Configured while running, it publishes nothing and reports no
error; rebooted with the client already attached, it publishes immediately. This
cost an hour. Two firmware suspects were read and cleared on the way: the
`DontMqttMeBro` filter does not apply, because `10.0.0.0/8` is in the firmware's
own private-range list, and the receive path does call the uplink for packets
that are not ours.

**Uplink is per channel and off by default.** With `mqtt.enabled` set and every
channel's `uplink_enabled` false, the radio connects and republishes nothing.
Channel 0 is the one that matters, because that is where the shared mesh is.

