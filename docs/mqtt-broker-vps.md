# Running the MQTT broker on a VPS

Notes for #10. The bench broker proved the mechanism (#7) but cannot serve a
multi-site link: it listens on a private LAN address that SJC and SNA cannot
reach. A broker for the real link has to be somewhere both ends can reach — a
VPS, or a private network joining the sites.

This assumes **Ubuntu 22.04** and mosquitto. Note 22.04 ships **mosquitto
2.0.11**; the bench used 2.0.18. Both are 2.x, so the defaults described here
hold: 2.x listens on localhost only and denies anonymous unless told otherwise.

## Why this needs care

A Meshtastic broker is not a passive relay. With downlink enabled, **anyone who
can publish to the right topic makes your radio transmit** (#7):

```json
{"from": 4143681024, "type": "sendtext", "payload": "..."}
```

That is the whole point of the mechanism and also its entire risk. An open
broker is a remote keying line into a transmitter you are licensed and
responsible for. Treat write access to the downlink topic as equivalent to
physical access to the radio.

Three distinct exposures, in descending order of seriousness:

| Exposure | Consequence |
|---|---|
| **Unauthorised publish to the downlink topic** | Third parties transmit through your radio, under your responsibility |
| **Unauthorised subscribe** | Position, telemetry and message metadata leak; with the default PSK, message content too |
| **Open broker generally** | Your VPS becomes someone else's free message bus, and your bandwidth bill |

## Sizing

Trivial. Three nodes exchanging text is a handful of messages per minute. The
smallest instance any provider sells — 1 vCPU, 512 MB–1 GB — is ample, and
mosquitto idles at a few MB of RAM. Pick the provider on network reliability and
jurisdiction, not specs.

## Install

```bash
sudo apt update
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable --now mosquitto
```

The package creates a `mosquitto` system user and runs the daemon as it. Do not
change that.

## Hardening

Put everything in one file under `conf.d/` rather than editing the shipped
`mosquitto.conf`, so upgrades do not clobber it.

### 1. Authentication — never anonymous

```bash
sudo mosquitto_passwd -c /etc/mosquitto/passwd ftg1
sudo mosquitto_passwd    /etc/mosquitto/passwd sjc
sudo mosquitto_passwd    /etc/mosquitto/passwd sna
sudo chown root:mosquitto /etc/mosquitto/passwd
sudo chmod 640 /etc/mosquitto/passwd
```

**One account per node, never a shared one.** Shared credentials cannot be
revoked selectively, and when SJC's phone is lost you want to disable exactly
that account.

`allow_anonymous true` is correct on a bench LAN and indefensible on a public
host.

### 2. TLS — mandatory on a public broker

Without it, credentials and traffic cross the internet in clear text.

```bash
sudo apt install -y certbot
sudo certbot certonly --standalone -d mqtt.example.com
```

Let's Encrypt is a public CA, so Meshtastic's `tls_enabled` validates it against
the built-in bundle with no extra configuration. A self-signed certificate
would need a CA the firmware does not carry — avoid it.

Certificates renew every 90 days and mosquitto must reload to pick them up:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/mosquitto.sh >/dev/null <<'EOF'
#!/bin/sh
install -o root -g mosquitto -m 640 \
  /etc/letsencrypt/live/mqtt.example.com/privkey.pem /etc/mosquitto/certs/privkey.pem
install -o root -g mosquitto -m 644 \
  /etc/letsencrypt/live/mqtt.example.com/fullchain.pem /etc/mosquitto/certs/fullchain.pem
systemctl reload mosquitto
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/mosquitto.sh
```

The copy matters: mosquitto drops privileges and cannot read
`/etc/letsencrypt/live` directly.

### 3. Topic ACLs — the control that actually contains the risk

Authentication proves who a client is. **ACLs decide what they may do**, and
without them any authenticated node can inject into any other's downlink topic.

```
# /etc/mosquitto/aclfile
# Nothing is permitted unless granted below.

user ftg1
topic readwrite msh/link/2/e/#
topic readwrite msh/link/2/json/#

user sjc
topic readwrite msh/link/2/e/#
topic readwrite msh/link/2/json/#

user sna
topic readwrite msh/link/2/e/#
topic readwrite msh/link/2/json/#

# An observer that may read but never transmit through anyone's radio.
user watch
topic read msh/link/2/e/#
topic read msh/link/2/json/#
```

```bash
sudo chown root:mosquitto /etc/mosquitto/aclfile
sudo chmod 640 /etc/mosquitto/aclfile
```

Use a **custom topic root** (`msh/link` above, set as `mqtt.root` on each node)
rather than the default `msh/US`. It keeps your tree separate from the public
convention and makes the ACL patterns unambiguous.

If you later want strict separation, give each node write access only to its own
gateway topic and read access to the others'. That prevents a compromised node
impersonating a sibling. The cost is a longer ACL and care when node IDs change.

### 4. The config file

```
# /etc/mosquitto/conf.d/link.conf
listener 8883
certfile /etc/mosquitto/certs/fullchain.pem
keyfile  /etc/mosquitto/certs/privkey.pem

allow_anonymous false
password_file /etc/mosquitto/passwd
acl_file /etc/mosquitto/aclfile

# Resource limits — a small broker has no reason to accept large or unbounded load
max_connections 20
message_size_limit 8192
max_queued_messages 200
max_inflight_messages 20

persistence true
persistence_location /var/lib/mosquitto/

log_dest file /var/log/mosquitto/mosquitto.log
log_type error
log_type warning
log_type notice
connection_messages true
```

Note there is **no plaintext 1883 listener**. Defining only 8883 means the
unencrypted port is never open. If you need 1883 for local testing on the VPS
itself, bind it explicitly to `127.0.0.1`.

`message_size_limit` is a cheap and effective abuse control: Meshtastic packets
are a few hundred bytes, so 8 KB is generous and still refuses anything trying to
use the broker as a file relay.

### 5. Firewall

```bash
sudo ufw default deny incoming
sudo ufw allow OpenSSH
sudo ufw allow 8883/tcp
sudo ufw enable
```

If all three sites have static addresses, narrow it further:

```bash
sudo ufw allow from <site-ip> to any port 8883 proto tcp
```

Most home connections do not have static addresses, so this is usually not
practical — which makes the ACLs and passwords the real perimeter, not the
firewall.

### 6. Host hygiene

```bash
sudo apt install -y unattended-upgrades fail2ban
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

SSH: keys only, no password authentication, no root login. Standard, and the
most likely way the box gets taken rather than anything MQTT-specific.

`fail2ban` ships a mosquitto jail in some versions; if not, the broker log
records failed authentications and a simple jail on
`/var/log/mosquitto/mosquitto.log` is straightforward.

## Node configuration

Per node, pointing at the VPS:

```bash
meshtastic --set mqtt.address mqtt.example.com \
           --set mqtt.username ftg1 \
           --set mqtt.password '<per-node-password>' \
           --set mqtt.tls_enabled true \
           --set mqtt.root msh/link \
           --set mqtt.encryption_enabled true
```

`mqtt.encryption_enabled true` keeps payloads encrypted with the channel PSK, so
the broker relays ciphertext and a broker compromise does not expose message
content. Leave it on unless a specific integration needs plaintext — and note
that **JSON downlink injection requires plaintext handling on the topic it uses**,
so keep that on a dedicated channel rather than the one carrying real traffic.

**Downlink belongs only on the dedicated `mqtt` channel** (#7), never on the
primary. On a private broker with ACLs the risk is contained; the habit is still
worth keeping.

## Verify before trusting it

```bash
# anonymous must be refused
mosquitto_sub -h mqtt.example.com -p 8883 --capath /etc/ssl/certs -t '#' -v

# plaintext port must not exist
nc -vz mqtt.example.com 1883

# a valid user must NOT be able to publish outside its ACL
mosquitto_pub -h mqtt.example.com -p 8883 --capath /etc/ssl/certs \
  -u watch -P '<pw>' -t 'msh/link/2/json/mqtt/' -m '{}'

# certificate chain must validate without -tls-insecure
openssl s_client -connect mqtt.example.com:8883 -servername mqtt.example.com </dev/null
```

The third is the one people skip. An ACL that is present but not working looks
identical to one that is working until someone tests it.

## The alternative worth weighing

A VPS is the straightforward answer, but it is not the only one. A VPN joining
the three sites — WireGuard, for instance — keeps the broker private and removes
the public attack surface entirely, at the cost of every site needing VPN
configuration. Given the downlink risk above, that is a real argument for it,
and worth deciding deliberately in #10 rather than defaulting to a public host.

A ham/AREDN backbone is sometimes suggested for this role. It is not
equivalent — see `aredn-as-a-transport.md`.

## Broker gotchas that cost real time

Moved here from `CLAUDE.md`. Each of these produced a silent or misleading
failure rather than a clear error.

- **The public broker will not do JSON downlink.** It restricts it, which is the
  whole reason a private broker exists.
- **amqtt is MQTT 3.1.1 only; the Meshtastic phone app speaks MQTT 5.0.** The
  broker answers `Unsupported protocol version` and the app reports
  `UNSUPPORTED_PROTOCOL_VERSION`. Use **mosquitto** — 2.0.18 handles both.
- **amqtt's `allow-anonymous: true` still rejects a client that supplies a
  username.** It permits clients sending *no* credentials. The node was sending
  `meshdev`/`large4cats` inherited from the public broker and got
  `Not authorized` — with no session established, and therefore nothing in the
  broker log to explain it.
- **mosquitto 2.x defaults to localhost-only and denies anonymous.** It needs
  `listener 1883 0.0.0.0` and `allow_anonymous true` in
  `/etc/mosquitto/conf.d/`.
