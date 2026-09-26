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
