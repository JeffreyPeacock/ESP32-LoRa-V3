# Second radio — SparkFun LoRa Gateway 1-Channel (ESP32)

Found on `/dev/ttyUSB1` on 2026-08-21. **Not a Heltec, and not the SAMD21 Pro RF
board** — different MCU family entirely.

## Identification

Read from the chip, not assumed:

| | |
|---|---|
| MCU | ESP32-D0WDQ6 rev v1.0, dual core, 240 MHz |
| Flash | **4 MB**, GigaDevice |
| MAC | `84:0d:8e:0c:5a:80` |
| USB bridge | CH340C (`1a86:7523`, driver `ch341`) |
| Radio | Hope **RFM95W** — an **SX1276**, not an SX1262 |

Every one of those matches the SparkFun schematic, which names `CH340C` and
`RFM95`. The board is the **original 2019 revision, WRL-15006**: SparkFun's
later revision (WRL-18074) is otherwise identical but carries **16 MB** of
flash, and this one reports 4 MB.

Both revisions are **retired** from SparkFun's catalogue.

## References

| | |
|---|---|
| Product page | <https://www.sparkfun.com/sparkfun-lora-gateway-1-channel-esp32.html> |
| Retired listing | <https://www.sparkfun.com/products/15006> |
| Hookup guide | <https://learn.sparkfun.com/tutorials/sparkfun-lora-gateway-1-channel-hookup-guide> |
| Hardware repo | <https://github.com/sparkfun/ESP32_LoRa_1Ch_Gateway> |
| Eagle files | <https://cdn.sparkfun.com/assets/2/7/0/0/e/ESP32_LoRa_1_Channel_Gateway.zip> |
| Gateway firmware | <https://github.com/things4u/ESP-1ch-Gateway> |
| LMIC library | <https://github.com/mcci-catena/arduino-lmic> |

Mirrored in `datasheets/`: the board schematic, the RFM95W datasheet, and the
ESP32 (non-S3) datasheet.

## What it is currently running

The stock **ESP-1ch-Gateway** sketch, i.e. what the hookup guide installs. Its
boot banner prints the stored configuration:

```
ESP32 defined, freq=903900000
.SF= 7   .CH= 0   .BOOTS= 26   .NTPS= 37
```

903.9 MHz is **US915 uplink channel 0**. The stored NTP timestamp is from March
2019, so it has not been reconfigured since.

**The banner prints the stored WiFi SSID and password in the clear on every
boot.** Reading it put a third party's credentials into a session log before
anything masked them; `scripts/export-transcript.sh` now has patterns for the
`.SSID=` / `.PASS=` shape. Be aware before pasting a boot capture anywhere.

## Why this matters to this project

- **Two radios means real link tests without SJC or SNA.** Until now every RF
  experiment depended on other operators.
- **It is SX127x, so it is not interchangeable with FTG1.** Different firmware
  targets throughout: `heltec-v2.1`/`tlora-v2` rather than `heltec-v3` for
  Meshtastic, and RNode menu option 7 rather than 8. The SX1262-specific facts
  in `CLAUDE.md` — 1.8 V TCXO, DIO2 as RF switch, DIO1 on GPIO14 — do **not**
  apply to this board.
- **On this chip Meshtastic's phone queue is 8 packets, not 32.** The 32-packet
  branch is guarded to ESP32-S3 and C3.
- **It is directly relevant to #14**, the LoRaWAN-gateway-to-Meshtastic bridge,
  because it already is a working LoRaWAN gateway.
- **But TTN v3 does not accept single-channel gateways.** SparkFun's own listing
  says so. It can still speak LoRaWAN to a private network server; it cannot
  join The Things Network as a gateway. That constrains #14.
