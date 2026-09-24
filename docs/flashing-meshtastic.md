# Flashing Meshtastic onto a Heltec V3

Moved out of `CLAUDE.md` on 2026-09-23. The finding that the vendor script
flashes to the wrong offset stays there, because it is a trap rather than a
procedure. This is the procedure.


The board holds one firmware at a time and there is no way to tell from the
outside. Check before assuming:

```bash
./scripts/heltec-dev.sh raw     # tap RST, read the banner, Ctrl-C
```

`==== Heltec WiFi LoRa 32 V3 bring-up ====` is the PlatformIO diagnostic;
Meshtastic and RNode announce themselves in their own boot logs.

**`./scripts/heltec-dev.sh flash` overwrites whatever is there** with the
PlatformIO diagnostic. That is the intended escape hatch for proving hardware,
but run `meshtastic --export-config` first if there is configuration worth
keeping — channel PSKs included, which is why those exports are gitignored.

As of 2026-09-01 FTG1 runs Meshtastic **2.7.26.54e0d8d**, target `heltec-v3`.

### Meshtastic's own `device-install.sh` flashes littlefs to the wrong offset

**Do not use it on this board.** Version 2.7.26's script reads the real spiffs
offset out of the `.mt.json` metadata and then ignores it:

```bash
SPIFFS_OFFSET=$(jq -r '.part[] | select(.subtype == "spiffs") | .offset' "$METAFILE")
...
$ESPTOOL_CMD ${ESPTOOL_WRITE_FLASH} $OFFSET "${SPIFFSFILE}"   # $OFFSET, not $SPIFFS_OFFSET
```

`$OFFSET` is a hardcoded `0x300000`. On the heltec-v3 8MB scheme spiffs is at
**`0x670000`**, and `0x300000` lands inside `app1` — so the script erases the
OTA image it wrote seconds earlier, and leaves the filesystem partition blank.
The board still boots, which is why this is easy to miss.

Flash the three images by hand at the offsets the metadata gives:

```bash
esptool --port <port> erase-flash
esptool --port <port> write-flash 0x0      firmware-heltec-v3-<ver>.factory.bin
esptool --port <port> write-flash 0x340000 mt-esp32s3-ota.bin
esptool --port <port> write-flash 0x670000 littlefs-heltec-v3-<ver>.bin
```

The script also refuses to run without `<target>.mt.json` and `mt-esp32s3-ota.bin`
beside the factory image; both are in the release zip, not in the per-board
subset we had saved. Verify every `md5sum` against the `files` list in the
metadata before flashing.

