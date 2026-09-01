# Configuring the radios without the CLI

GUI alternatives to `rnodeconf` and the `meshtastic` CLI, with the install steps
for each. Versions checked **2026-09-01** against the upstream release APIs;
versions move, the shapes do not.

**None of this adds capability.** `rnodeconf` and the `meshtastic` CLI already do
everything below. A GUI buys messaging, a readable parameter screen, and
something to hand a second operator — not new function.

Host assumptions throughout: **Ubuntu 24.04**, Python 3.12, and the udev rule
from `scripts/heltec-setup.sh` already installed. Anything that talks to a board
over USB needs the user in `dialout` and ModemManager kept off the tty — both are
what `heltec-setup.sh setup` arranges, so run it before any of this.

---

## Reticulum / RNode

### Sideband — the same app as on the phone

**2.1.0**, released 2026-08-28.

| Build | Size |
|---|---:|
| `Sideband_2.1.0_x86_64.appimage` | 148.5 MB |
| `Sideband_2.1.0_aarch64.appimage` | 156.7 MB |
| `Sideband_2.1.0_Windows.zip` | 115.6 MB |
| `sbapp-2.1.0-py3-none-any.whl` | 62.3 MB |
| `Sideband_2.1.0.apk` | 115.3 MB |

<https://github.com/markqvist/Sideband/releases/latest>

**APK-only distribution applies to Android, not to desktop.** Every asset is
signed; the release page carries a `.rsg` signature beside each file.

#### Install: AppImage — nothing to set up

```bash
cd ~/Downloads
curl -LO https://github.com/markqvist/Sideband/releases/latest/download/Sideband_2.1.0_x86_64.appimage
chmod +x Sideband_2.1.0_x86_64.appimage
./Sideband_2.1.0_x86_64.appimage
```

Voice calls, audio messages and clipboard need three system libraries the
AppImage does not bundle. Text messaging works without them:

```bash
sudo apt install libopusfile0 xclip xsel
```

#### Install: pip, into a virtualenv

Upstream tells you to run `pip install sbapp --break-system-packages`. **Do not
do that here.** This project already resolves Python tools out of a virtualenv
(`resolve_venv_bin()` in `scripts/lib/heltec-common.sh`), and Sideband pulls in
its own `rns` and `lxmf` — installing it system-wide would put a second copy of
Reticulum on the machine, at a different version from the one `rnsd` uses.

```bash
sudo apt install python3-pyaudio libopusfile0 codec2 xclip xsel

python3 -m venv ~/.venvs/sideband
~/.venvs/sideband/bin/pip install sbapp
~/.venvs/sideband/bin/sideband            # first run installs the desktop entry
```

Or into the existing pyenv layout, matching how the rest of this project is set
up:

```bash
pyenv virtualenv 3.12.12 sideband
~/.pyenv/versions/sideband/bin/pip install sbapp
```

Two flags worth knowing: `sideband --daemon` runs it headless (useful as a
telemetry collector), and `sideband -v` turns on verbose logging.

**Sideband brings its own Reticulum.** It reads `~/.reticulum/config`, the same
file `rnsd` reads, so it will pick up FTG1's interfaces — including the RNode —
without further configuration. That is also why it cannot run at the same time
as `rnsd` holding the same serial port. See "Only one host at a time" below.

#### Where the settings actually are

RNode parameters live under **Hardware → RNode** — frequency, bandwidth,
spreading factor, coding rate, TX power, beacon interval, airtime limits. The
interface is enabled **separately**, under **Preferences → Connectivity →
`Connect via RNode`**, and the RNS service must be restarted afterwards.

**Both steps fail silently if you do only one.** This cost real time; see
`Reticulum-exploration-notes.md`.

### MeshChat — an Electron alternative

**v2.4.0**, released 2026-07-06. Same Reticulum underneath, different interface.

<https://github.com/liamcottle/reticulum-meshchat/releases/latest>

| Build | Size |
|---|---:|
| `ReticulumMeshChat-v2.4.0-linux.AppImage` | 154.7 MB |
| `ReticulumMeshChat-v2.4.0-mac-arm64.dmg` | 151.4 MB |
| `ReticulumMeshChat-v2.4.0-mac-x64.dmg` | 153.0 MB |
| `ReticulumMeshChat-v2.4.0-win-installer.exe` | 90.9 MB |
| `ReticulumMeshChat-v2.4.0-win-portable.exe` | 90.6 MB |

#### Install: AppImage

```bash
cd ~/Downloads
curl -LO https://github.com/liamcottle/reticulum-meshchat/releases/download/v2.4.0/ReticulumMeshChat-v2.4.0-linux.AppImage
chmod +x ReticulumMeshChat-v2.4.0-linux.AppImage
./ReticulumMeshChat-v2.4.0-linux.AppImage
```

#### Install: from source

It is a Python Reticulum instance plus a WebSocket server, with a browser front
end — the Electron build just bundles a browser around that. Needs **Node 18+**
and Python 3:

```bash
git clone https://github.com/liamcottle/reticulum-meshchat.git
cd reticulum-meshchat
npm install --omit=dev
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python meshchat.py
```

`--headless` runs it without opening a browser, and `--identity-file PATH` points
it at an existing Reticulum identity rather than generating one. **Use
`--identity-file`** if you want it to be the same LXMF address as FTG1; by
default it makes a new one, which is the same trap `lxmd` sprang in #15.

---

## Meshtastic

**FTG1 currently runs RNode, so everything in this section needs a reflash
first.** See the rollback command in `README.md`.

### The node's own web UI — nothing to install

Ports 80/443 on the node itself. No installation, no internet, no account. Only
available while the node is on WiFi, which means **BLE is off** — see "Reaching
a headless node on WiFi" in `CLAUDE.md`.

### The web client, self-hosted

`meshtastic/web` **v2.7.2**, released 2026-08-09, GPL-3.0.
<https://github.com/meshtastic/web>

#### Install: the prebuilt bundle — no Node needed

The release ships a 2 MB `build.tar` of static files. Serve it with anything:

```bash
mkdir -p ~/meshtastic-web && cd ~/meshtastic-web
curl -LO https://github.com/meshtastic/web/releases/latest/download/build.tar
tar xf build.tar
python3 -m http.server 8080
```

Then open <http://localhost:8080>. This is the shortest path and the one to
prefer — it needs no JavaScript toolchain at all.

#### Install: from source

The repository is a pnpm monorepo — the SDK, the transports and the client all
live in it. **`pnpm` is not installed on this machine**; `npm i -g pnpm` or use
`corepack enable`.

```bash
git clone https://github.com/meshtastic/web.git
cd web
pnpm install
pnpm --filter @meshtastic/web dev
```

Four transports are available: **Web Serial** over USB, **Web Bluetooth**,
**HTTP** to a networked node, and TCP under Node/Deno.

**Web Serial over USB is the useful one here.** It needs nothing on the node's
network side, so BLE stays available — unlike the built-in web UI, which forces
WiFi on.

### The hosted client — nothing to install

<https://client.meshtastic.org> is the same application served publicly. It talks
to the device directly over Web Serial or Web Bluetooth, so **mesh data does not
reach their server** — but the page itself is fetched over the internet, which is
why self-hosting is the better answer to "run it locally".

<https://flasher.meshtastic.org> is the browser-based firmware flasher, the
equivalent of the release `device-install.sh` this project uses.

### Not a config tool

`org.meshtastic.meshtasticd` on Flathub is the Linux **daemon** — a Meshtastic
node running on the PC itself, not a UI for the Heltec.

---

## Two constraints worth knowing before choosing

**Web Serial is Chrome and Edge only.** Firefox does not implement it, so any
browser-based option that talks over USB rules Firefox out.

**Only one host at a time.** The board serves either the USB serial port or its
BLE link, not both, and only one process can hold the serial port. A GUI cannot
configure a board while `rnsd`, `lxmd` or a phone holds it — the symptom is a
silent non-response, not an error. Stop the other host first:

```bash
pgrep -af 'rnsd|lxmd|sideband'
```
