# Power budget for the Heltec WiFi LoRa 32 V3

Whole-board figures from the vendor datasheet, not estimated from the radio
alone. Vendor PDFs for every chip on the board are mirrored in
`docs/datasheets/`; read them there rather than from memory or a web search.

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
component datasheets gave 55 mA, about half the real figure, because the
whole-board number includes the regulator, the OLED and the USB bridge. **Use
the table, not arithmetic from the SX1262 alone.**

**The screen and BLE cost more than transmitting** — TX is 230 mA but the duty
cycle is tiny, and the ESP32 staying awake to listen dominates. Multi-day
runtimes need `is_power_saving`, which disables Bluetooth, WiFi and the screen:
a beacon, not a messaging device.

**USB/battery switching is automatic** — with USB attached the board runs from
USB and charges the pack. USB together with the 5V pin is the one combination
that is not allowed.

## Why the estimate was wrong

Adding up the component datasheets gave 55 mA, which is about half the measured
whole-board figure. The gap is the parts that are easy to forget: the regulator,
the OLED and the USB-serial bridge all draw current whether or not the radio is
doing anything. **Use the table above rather than arithmetic from the SX1262.**

## FTG1 rides out a power cut, for about a day

**FTG1 has a 3000 mAh pack attached as well as USB, confirmed by looking at the
connector on 2026-09-26.** Earlier notes here and in `CLAUDE.md` implied no pack
was fitted. The consequence is not about runtime on a bench, it is about what
survives an outage, and the parts fail in a specific order:

- **USB unplugged, or pi4 powered off, house power up.** FTG1 keeps running on
  the pack and keeps its WiFi, so it stays a full participant on the RF mesh.
  **But the broker is on pi4**, so MQTT uplink fails and meshview ingests
  nothing. The node is alive, the public site is stale, and nothing on the radio
  reports the difference.
- **House power out.** The access point goes too, so FTG1 has no WiFi and no
  broker. It continues as an RF-only node, which is the case Meshtastic exists
  for, and is the most useful thing it can be doing in an outage.

Runtime is arithmetic from the table above, not a measurement: WiFi is on
continuously at 115–150 mA, so 3000 mAh gives roughly **20 to 26 hours**. The
screen is not a factor after the first ten minutes — `screen_on_secs` is 600.
`is_power_saving` is **off**, which is correct for a gateway and is why the
figure is a day rather than several.

**`on_battery_shutdown_after_secs` is 0**, so there is no graceful shutdown: the
node runs until the pack is flat. That maximises uptime during an outage and
deep-discharges the cell, which is a deliberate trade worth knowing about rather
than a default worth keeping by accident.

Two consequences for configuration. The battery voltage is now the **only signal
that distinguishes mains from battery**, which is a reason to publish device
telemetry rather than to suppress it. The earlier reason for suppressing it was
that the reading was a floating charger rail, and that no longer applies. The
reading is real but **uncalibrated**: `VBAT_DIVIDER` is unverified (#11) and the
`ADC_CTRL` polarity is unsettled (#13), so treat the percentage as an indicator
of state, not a measurement.
