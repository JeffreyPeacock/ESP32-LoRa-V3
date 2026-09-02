# Moving FTG1 and the listener to a Raspberry Pi 4 (Debian 13, Trixie)

The desktop is too busy to hold a radio permanently. This is what transfers
cleanly, what does not, and what has to be configured on the Pi.

**Nothing here has been tested on a Pi.** It is analysis of the actual
dependencies plus the parts of this project that are known to be
host-specific. Every claim about the software is checked against the packages;
every claim about the hardware is inference from the desktop's behaviour.

## What transfers with no work

**The Python side is architecture-independent.** `meshtastic` publishes a
`py3-none-any` wheel and declares support for Python 3.9 through 3.14, so
Trixie's **Python 3.13** is inside its range with room to spare. Every runtime
dependency — `bleak`, `protobuf`, `pypubsub`, `pyserial`, `pyyaml`, `requests` —
ships either a pure-Python wheel or a `manylinux aarch64` one. **Nothing
compiles**, so no build toolchain is needed on the Pi.

**The listener itself has no host-specific code.** It talks to a serial port
and hands mail to `/usr/sbin/sendmail`. Both exist on Debian 13.

**The CP2102N driver is in the mainline kernel.** `cp210x` is present on
Debian arm64, the same module the desktop uses.

**PlatformIO is not needed.** The Pi never compiles firmware. Run the installer
with `--skip-platformio` and skip roughly 2 GB.

## What will not transfer, and will bite

### The serial path is wrong the moment you move the board

`etc/secrets/listener.conf` names
`/dev/serial/by-path/pci-0000:00:14.0-usb-0:3:1.0-port0`. That is a **PCI**
address. The Pi 4's USB comes off an on-SoC XHCI controller, so its by-path
names look like `platform-xhci-hcd.1-usb-0:1.3:1.0-port0` instead. The old
value will not merely be wrong, it will not exist.

Re-read it on the Pi and confirm the board by MAC, never by port number:

```bash
./scripts/heltec-dev.sh ports
./scripts/heltec-dev.sh chip-id /dev/ttyUSB0     # expect 44:1b:f6:fb:8e:00
```

Then set `[listen] port` to the by-path name. This is the same rule recorded in
`CLAUDE.md`: **a by-path name identifies the USB socket, not the board.** Pick
one socket on the Pi and leave the radio in it.

### Mail is the real dependency, and it is not installed by default

**Configure this first.** Nothing else can be validated without it: the
listener's only outputs are email and SMS, and SMS is email. Get mail working
on the Pi before the radio is even plugged in — `self-test` needs no radio, so
mail can be proven on its own.

#### The working configuration, from this desktop

Install postfix and choose **"Satellite system"** when debconf asks; that is
the profile this needs — deliver nothing locally, relay everything to a
smarthost. Then set:

```
relayhost                  = [mail.wonkware.com]:587
smtp_sasl_auth_enable      = yes
smtp_sasl_password_maps    = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level    = encrypt
smtp_tls_CApath            = /etc/ssl/certs
smtp_generic_maps          = hash:/etc/postfix/generic
smtp_address_preference    = ipv4
inet_interfaces            = loopback-only
```

`inet_interfaces = loopback-only` matters: the Pi must not accept mail from
the network, only from itself.

Applied as commands:

```bash
sudo apt install postfix                     # choose "Satellite system"
sudo postconf -e 'relayhost = [mail.wonkware.com]:587' \
  'smtp_sasl_auth_enable = yes' \
  'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd' \
  'smtp_sasl_security_options = noanonymous' \
  'smtp_tls_security_level = encrypt' \
  'smtp_tls_CApath = /etc/ssl/certs' \
  'smtp_generic_maps = hash:/etc/postfix/generic' \
  'smtp_address_preference = ipv4' \
  'inet_interfaces = loopback-only'
```

#### The two map files

**Credentials.** `/etc/postfix/sasl_passwd` is `0600`, root-owned, and its
contents are **not in this repository**. One line, from whoever administers the
relay:

```bash
sudo install -m 600 /dev/null /etc/postfix/sasl_passwd
sudo tee /etc/postfix/sasl_passwd >/dev/null <<'EOF'
[mail.wonkware.com]:587    USER:PASSWORD
EOF
sudo postmap /etc/postfix/sasl_passwd
```

**Sender rewriting**, which is what makes the From address correct and DMARC
align. The listener sends as `ftg1@ftg`; this maps it onto the real domain:

```bash
sudo tee -a /etc/postfix/generic >/dev/null <<'EOF'
ftg1@ftg    ftg1@flagstafftechgroup.org
EOF
sudo postmap /etc/postfix/generic
sudo systemctl reload postfix
```

That sender is not arbitrary — `flagstafftechgroup.org` publishes
`v=spf1 include:wonkware.com -all`, and `wonkware.com` lists the relay's IP, so
SPF passes and DMARC aligns. **A sender on a domain that does not authorise the
relay fails SPF and scores worse than an unbranded address**, so do not
substitute a different one without checking:

```bash
dig +short TXT flagstafftechgroup.org | grep spf1
dig +short A mail.wonkware.com
```

#### Prove it before going further

```bash
printf 'Subject: pi mail test\nTo: you@example.com\n\nbody\n' \
  | sendmail -f ftg1@ftg -t
sudo journalctl -u postfix -n 20 --no-pager | grep -E 'status=|from=<'
```

Look for `status=sent (250 ...)` and `from=<ftg1@ftg>`. Anything else — a
`status=bounced`, an auth failure, a `Connection refused` — is a mail problem
to finish before touching the radio. Then, once the checkout exists:

```bash
./scripts/meshtastic-listener.sh self-test -d FTG1
```

which exercises the real code path, including the phone book, with no radio
attached.

#### Why one relay covers both

Both notification paths go through the local MTA, because **an SMS here is an
email** to a carrier gateway. There is no second service and no second
credential to manage.

Without it the listener still records everything to the ledger — it just cannot
tell anyone. That failure is visible in the journal and in the ledger's
`email_sent` / `sms_sent` fields, so it is loud rather than silent.

### `pip install` into the system Python is blocked

Debian 13 marks its Python as externally managed (PEP 668), so a system-wide
`pip install` fails by design. That is already this project's pattern — use a
virtualenv in the checkout, which `resolve_venv_bin()` finds without being
told:

```bash
python3 -m venv .venv
.venv/bin/pip install meshtastic esptool
```

No pyenv required. See "Python environment" in `README.md`.

### A user unit will not survive a headless reboot

The listener runs as a **user** unit on the desktop, which is right for a
workstation but wrong for an appliance: a user unit stops at logout and does
not start at boot unless lingering is enabled. On a headless Pi, install it as
a **system** unit instead — it still runs as your account rather than root,
because the ledger lives in the checkout and root-owned files there break the
next ordinary run:

```bash
./scripts/meshtastic-listener.sh install-service -s
sudo systemctl enable --now meshtastic-listener
journalctl -u meshtastic-listener -f
```

`install-service` writes the unit with this checkout's real paths. It is
generated rather than committed on purpose — a unit file with someone else's
home directory baked into it is worse than no unit at all.

## Services to configure on the Pi

| Service | Why | Command |
|---|---|---|
| **postfix** | both email and SMS; satellite/relay to the smarthost | `sudo apt install postfix` |
| **meshtastic-listener** | the listener itself | `./scripts/meshtastic-listener.sh install-service -s` |
| **udev rule** | keeps ModemManager off the tty | `./scripts/heltec-setup.sh setup` |
| **dialout** | serial access without root | `./scripts/heltec-setup.sh add-dialout` |
| **systemd-timesyncd** | usually on already — see below | `timedatectl status` |
| **ssh** | it is headless | `sudo systemctl enable --now ssh` |

### Time matters more on a Pi than on the desktop

**A Pi 4 has no battery-backed clock.** It boots believing it is whenever it
last shut down until NTP corrects it. The ledger's `received_at` is the host
clock, so messages that arrive in the first seconds after a cold boot get
timestamps that are wrong, sometimes by a lot. Confirm `timedatectl` reports
`System clock synchronized: yes`, and consider a small RTC module if the Pi
will run somewhere without reliable network at boot.

## Power, which is the most likely thing to go wrong

The radio draws **90 mA receiving and 230 mA transmitting at 22 dBm**
(datasheet Table 3.4, whole board). A Pi 4's USB ports supply far more than
that, so the radio is not the problem.

**The Pi's own supply is.** A Pi 4 wants a genuine 5 V / 3 A source. Under an
inadequate one the USB ports brown out under load, and the symptom is a serial
device that disappears and reappears — which will look exactly like a failing
radio. Check for it before blaming the board:

```bash
vcgencmd get_throttled     # 0x0 is healthy; bit 0 set means under-voltage now
dmesg | grep -i 'under-voltage\|usb disconnect'
```

The listener restarts on a vanished port, so undervoltage will show up as a
reconnect loop in the journal rather than an outage.

## Worth doing while the radio is off the desktop

`etc/rnode/RESTORE.md` covers putting RNode back. Note that a Pi is a
*better* host for Reticulum than for Meshtastic — `rnsd` wants to run
continuously and a low-power always-on box is exactly right for a transport or
propagation node, which is the direction #15 points.

## Sequence

Mail first — see above. Nothing below can be validated until `sendmail` reaches
the relay.

```bash
# on the Pi
sudo apt install git postfix
git clone git@github.com:JeffreyPeacock/ESP32-LoRa-V3.git
cd ESP32-LoRa-V3
python3 -m venv .venv && .venv/bin/pip install meshtastic esptool

./scripts/heltec-setup.sh setup          # udev rule, dialout; prompts for sudo
./scripts/heltec-dev.sh ports            # read the real by-path name
./scripts/heltec-dev.sh chip-id <port>   # confirm MAC 44:1b:f6:fb:8e:00

mkdir -p etc/secrets
cp etc/listener.conf.example etc/secrets/listener.conf
#   edit [listen] port  -> the by-path name just read
#   copy etc/secrets/sms-phones.json across (it is gitignored, so move it by hand)

./scripts/meshtastic-listener.sh check
./scripts/meshtastic-listener.sh self-test -d FTG1    # proves mail and SMS
./scripts/meshtastic-listener.sh install-service -s
sudo systemctl enable --now meshtastic-listener
```

`check` verifies the config, the port and whether anything already holds it.
`self-test` proves both notification paths before you depend on them — and
remember that the relay accepting a message is not the handset receiving it.

## What does not move

**The node identity stays with the board, not the host.** `!f6fb8e00`, the
channels, the PKI keys and the fixed position all live in the radio's flash.
Moving it to a different computer changes nothing on the air.

**The phone keeps talking to FTG2**, which is unaffected by any of this.
