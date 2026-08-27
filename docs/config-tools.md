# Configuring the radios without the CLI

Options for driving these boards from a GUI instead of `rnodeconf` and
`meshtastic`. Checked 2026-08-27; versions move, the shapes do not.

**None of this adds capability.** `rnodeconf` and the `meshtastic` CLI already do
everything below. A GUI buys messaging, a readable parameter screen, and
something to hand a second operator — not new function.

## Reticulum / RNode

### Sideband — the same app as on the phone

Version 2.0.1 ships desktop builds alongside the Android APK:

| Build | Size |
|---|---|
| `Sideband_2.0.1_x86_64.appimage` | 148 MB |
| `Sideband_2.0.1_aarch64.appimage` | 156 MB |
| `Sideband_2.0.1_Windows.zip` | 115 MB |
| `sbapp-2.0.1-py3-none-any.whl` | 62 MB |

<https://github.com/markqvist/Sideband/releases>

**APK-only distribution applies to Android, not to desktop.** The wheel installs
into a virtualenv, which suits the layout this project already uses; the
AppImage needs nothing.

RNode settings live under **Hardware → RNode** — frequency, bandwidth, spreading
factor, coding rate, TX power, beacon interval, airtime limits. The interface is
enabled separately under **Preferences → Connectivity → `Connect via RNode`**,
and the RNS service must be restarted afterwards. See
`Reticulum-exploration-notes.md`; both steps fail silently.

### MeshChat — an Electron alternative

v2.4.0, with Linux AppImage, macOS (arm64 and x64) and Windows builds.
<https://github.com/liamcottle/reticulum-meshchat/releases>

Different interface, same Reticulum underneath.

## Meshtastic

**The board currently runs RNode, so all of this needs a reflash first.**

### The node's own web UI — nothing to install

Ports 80/443 on the node itself. No installation, no internet, no account. Only
available while the node is on WiFi, which means **BLE is off** — see "Reaching
a headless node on WiFi" in `CLAUDE.md`.

### The web client, self-hosted

`meshtastic/web`, v2.7.2, GPL-3.0. Runs locally:

```bash
pnpm --filter @meshtastic/web dev
```

<https://github.com/meshtastic/web>

Four transports: **Web Serial** over USB, **Web Bluetooth**, **HTTP** to a
networked node, and TCP under Node/Deno.

**Web Serial over USB is the useful one here.** It needs nothing on the node's
network side, so BLE stays available — unlike the built-in web UI, which forces
WiFi on.

### The hosted client

<https://client.meshtastic.org> is the same application served publicly. It
talks to the device directly over Web Serial or Web Bluetooth, so **mesh data
does not reach their server** — but the page itself is fetched over the
internet, which is why self-hosting is the better answer to "run it locally".

<https://flasher.meshtastic.org> is the browser-based firmware flasher, the
equivalent of the release `device-install.sh` we use.

### Not a config tool

`org.meshtastic.meshtasticd` on Flathub is the Linux **daemon** — a Meshtastic
node running on the PC itself, not a UI for the Heltec.

## Two constraints worth knowing before choosing

**Web Serial is Chrome and Edge only.** Firefox does not implement it, so any
browser-based option that talks over USB rules Firefox out.

**Only one host at a time.** The board serves either the USB serial port or its
BLE link, not both. A GUI cannot configure a board while `rnsd` or a phone holds
it — the symptom is a silent non-response, not an error. Stop the other host
first.
