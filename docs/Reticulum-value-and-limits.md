# What Reticulum is for, and what it will not do

Written for someone deciding whether this is worth the trouble. It answers three
questions we actually hit while building the two-node link: what the point is,
how two RNodes reach each other over distance, and whether a message survives the
recipient being switched off.

Facts here were measured on our own hardware or read from the source, not
assumed. Working notes are in `Reticulum-exploration-notes.md`; the concepts are
in `Reticulum-Overview.md`.

## The value proposition, plainly

**Your address belongs to you.** It is a hash of a keypair generated on your own
device and registered with nobody. There is no account, no phone number, no
provider, and nothing that can be suspended. Our phone's address,
`d734ac787e37b49a4466dd8be4a70fe7`, was created on the handset and was unknown to
the world until it announced itself.

**Relays cannot read what they carry.** Encryption is end-to-end with no
plaintext mode. The community backbone nodes we route through move ciphertext
and could not decrypt it if they wanted to.

**The transport does not matter.** The same address and the same message travel
over LoRa, TCP, I2P, packet radio or a serial cable, and can change transport
partway. This is the property that distinguishes it from a normal messenger,
which speaks IP to one company's servers and nothing else.

**It degrades in parts rather than all at once.** Lose the internet and anything
still reachable by radio keeps working. Lose the radio and anything reachable
over IP keeps working.

### Be honest about where it is ordinary

**Between two sites that both have good internet, this is topologically the same
as any messenger.** Endpoint, local link, internet, local link, endpoint. The
LoRa is an access hop; the internet does the distance. Anyone claiming a
900 km "mesh" in that configuration is overselling it.

What is genuinely different in that case is narrower, and worth stating in one
line: **nobody issues the addresses, and nobody in the middle can read the
traffic.** The rest of the advantage only appears when infrastructure is
missing, degraded, or hostile.

## How two RNodes talk over distance

An RNode is a **modem, not a node**. It does the radio; a host beside it runs
Reticulum. That host can be a laptop, a Raspberry Pi, or a phone over Bluetooth
— phone plus RNode is a complete, self-contained node.

Three ways to span distance, in increasing order of what they need:

**1. Direct RF.** One radio to the other. Limited by the link budget and the
horizon — kilometres in the open, more with elevation. Our two boards are on the
same desk. This needs nothing at all: no internet, no infrastructure, no third
party. **Proven here:** a message crossed from one board to the other with the
receiving instance having no interface except its radio.

**2. Relayed RF.** An intermediate node with `enable_transport = True` forwards
between nodes that cannot hear each other. Chain enough and coverage grows —
but every relay is a host someone has to run and power. Ours are leaves and
forward nothing.

**3. A non-RF bridge.** Any node with two interfaces joins two worlds. Ours has
a radio and three internet links, so it reaches 300-odd destinations that no
amount of LoRa could. The bridge does **not** have to be the public internet —
a VPN, cellular, or a ham/AREDN network carries IP just the same.

**But AREDN is not a drop-in answer for Reticulum, and an earlier draft of this
document wrongly implied it was.** AREDN operates under FCC Part 97, which
prohibits "messages encoded for the purpose of obscuring their meaning"
(97.113-a-4), and AREDN's own documentation advises against running software
that encrypts. Reticulum encrypts everything and has no plaintext mode, so
Reticulum-over-AREDN is legally doubtful in the US rather than merely
unconventional. We have already seen the same rule bite in practice: the
licensed operator `!8c36d408` (KJ7PJE) runs Meshtastic with `is_licensed: true`,
which **disables encryption**, and his packets arrive in the clear.

A VPN over commercial internet, or cellular, has no such constraint. AREDN
remains interesting as an IP backbone for *unencrypted* traffic; it is not a way
to run this stack free of that trade-off.

**Flagstaff to San Jose is ~900 km. No number of LoRa hops closes that.** A
backbone is required, and the only real decision is which transport carries it.

### What both ends must agree on

There is **no LongFast equivalent** — no default channel everyone lands on. Two
RNodes must match **frequency, bandwidth, spreading factor and coding rate** in
advance or they never hear each other. Not an error, not a partial contact:
silence. Ours are 915 MHz / 125 kHz / SF8 / CR5, which is a local convention and
nothing more.

This is why a Meshtastic survey here found 105 nodes and a Reticulum survey
found none. Meshtastic has a shared default; Reticulum does not.

## If the recipient is switched off

The honest answer is **not by default, and it needs infrastructure you have to
provide.**

**Direct delivery fails.** LXMF's `DIRECT` method needs the recipient reachable
now. The router retries — `MAX_DELIVERY_ATTEMPTS = 5`, ten seconds apart — and
then calls `fail_message`. Nothing is held anywhere. Turning the phone on later
does not produce the message, because it was never stored.

**Propagated delivery works, if a propagation node exists.** With LXMF's
`PROPAGATED` method the sender hands the message to a propagation node, which
stores it; the recipient syncs from that node when it next comes up. This is the
store-and-forward the whole stack is interesting for, and it is the thing
Meshtastic has no equivalent of — its MQTT bridge relays in real time and queues
nothing.

The catches, and they are the point:

- **Somebody must run one.** It is another Reticulum instance with
  `enable_node = yes`, on a host that stays up. Ours is deliberately off —
  running one is a commitment to store other people's mail.
- **Both ends must be able to reach it.** A propagation node only helps if the
  sender can deliver to it and the recipient can later sync from it. For two
  battery nodes going in and out of coverage, that usually means the propagation
  node sits somewhere always-on with a backbone.
- **The sender must choose it.** Sideband has an `LXMF Propagation Node` setting
  and a `Try propagation automatically` option. Left unset, messages go direct
  and fail against an offline recipient.

So for the specific case — two battery-powered RNodes on phones, one switched
off — the message arrives later **only if a propagation node both can reach was
in the path**. Otherwise it fails at the sender and is gone.

**This is untested here.** It is the open item on #15: stand up a propagation
node, take the recipient offline, send, bring it back, and confirm.

## Runtime, since these are meant to travel

The Heltec datasheet gives **90 mA receiving** for the whole board, so roughly
**one day on a 3000 mAh pack**. RNode has no equivalent of Meshtastic's
power-saving modes, and its display and Bluetooth stay on. Plan for a day
untethered, not a week.

Bench work runs both radios at **2 dBm** because they are inches apart and full
power overloads the receiver. **Put it back to 17–22 dBm before going out**, or
the range will be a few metres.
