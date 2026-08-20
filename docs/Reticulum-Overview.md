# Reticulum — a short primer

Why this project cares: Meshtastic floods packets across one RF domain and
queues nothing for an absent recipient. Reticulum is an actually routed network
with path tables, transport-agnostic links, and store-and-forward delivery. See
`Reticulum-exploration-notes.md` for what we measured on FTG1.

## Primary sources

| | |
|---|---|
| Project site | <https://reticulum.network/> |
| Manual | <https://markqvist.github.io/Reticulum/manual/> |
| Reticulum (RNS) | <https://github.com/markqvist/Reticulum> |
| LXMF, the messaging layer | <https://github.com/markqvist/LXMF> |
| Nomad Network, terminal client | <https://github.com/markqvist/NomadNet> |
| Sideband, desktop/mobile client | <https://github.com/markqvist/Sideband> |
| MeshChat, web client | <https://github.com/liamcottle/reticulum-meshchat> |
| RNode hardware and firmware | <https://unsigned.io/> |
| Live interface directory | <https://rmap.world/> (JSON at `/?json=1`) |

## The model, in six ideas

**Identity.** A keypair — Ed25519 for signing, X25519 for key exchange. It is
generated locally and registered with nobody. There is no authority, no DNS, no
address allocation. Losing the private key loses the address permanently.

**Destination.** An identity plus an app name and aspects, hashed to a 16-byte
address, written like `<a607467c5923a1281475ee4310c6fea0>`. One identity can
carry many destinations. The address *is* the hash of the key, so an address is
self-authenticating: nobody can claim one without holding the key.

**Announce.** A destination advertises itself; nodes that hear it record a path
back. This is how anything becomes reachable. No announce, no route.

**Transport node.** An instance with `enable_transport = True` relays for others
and maintains a path table. Paths are **cached with an expiry** — we observed
week-long entries — rather than reflooded per packet, which is the concrete
difference from Meshtastic. FTG1 runs as a leaf, not a transport node.

**Interface.** How packets physically move: `RNodeInterface` for LoRa,
`TCPClientInterface` and `BackboneInterface` over IP, plus I2P, serial, KISS and
AX.25. **The stack does not care which**, and one instance can bridge several —
which is exactly the multi-site problem this project has, solved at the right
layer.

**Link.** An encrypted, forward-secret session between two destinations, set up
end to end. Encryption is not optional and there is no plaintext mode; relays
carry ciphertext and cannot read it.

## LXMF, and what "an identity and an LXMF address" means

Reticulum itself moves bytes. **LXMF** (Lightweight Extensible Message Format)
is the messaging layer on top — the thing that corresponds to a Meshtastic text
message. An **LXMF address** is a destination hash for the `lxmf.delivery` app,
derived from your identity.

So the phrase means two concrete steps:

1. Generate an identity — `rnid -g <path>` — a keypair on disk.
2. Run an LXMF client (Nomad Network, Sideband or MeshChat), which derives a
   `lxmf.delivery` destination from it and announces it.

Until that exists, FTG1 can route packets but has no address anyone can send a
message to. It is reachable in the way a switch is reachable, not the way a
mailbox is.

**Propagation nodes** are the payoff. An LXMF propagation node stores messages
for recipients that are offline and delivers them when they reappear. That is
the capability Meshtastic has no equivalent of — its MQTT bridge relays in real
time and holds nothing. On this board it matters that store-and-forward here is
a network service, not an on-device buffer, so it does not depend on the PSRAM
the V3 lacks.

## What it is not

- **Not a Meshtastic replacement on the same air.** Different framing and sync
  word; the two cannot hear each other regardless of frequency.
- **Not zero-configuration over RF.** There is no LongFast equivalent. Two
  RNodes must agree frequency, bandwidth, spreading factor and coding rate.
- **Not anonymous by default.** Traffic is encrypted, but announces are public
  and the discovery system can publish interface details including position.
