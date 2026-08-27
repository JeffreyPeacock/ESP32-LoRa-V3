# AREDN as an optional radio transport

**Reference only. Nothing in this project plans to use it**, and neither this
operator nor the one at SJC intends to bring up a node. It is written down so
the question does not have to be researched again, and because one fact about it
is easy to miss and would waste a lot of effort.

## What it is

**AREDN — Amateur Radio Emergency Data Network.** Replacement firmware for
commercial wireless hardware (Ubiquiti, Mikrotik, Netgear, and 802.11ah "HaLow"
900 MHz radios) that turns it into a licensed amateur network instead of
consumer WiFi.

What it produces is **an ordinary IP network built out of radio links**. Nodes
find each other and self-organise; current releases route with **Babel**, having
dropped OLSR. Because it is plain IP it will carry anything — including an MQTT
connection or a Reticulum `TCPInterface`.

Its appeal is that it runs under **FCC Part 97** rather than Part 15: amateur
allocations near the WiFi bands, and legal power and antenna gain far above
consumer limits. With directional antennas and line of sight, backbone hops of
tens of kilometres are routine. That is why it comes up whenever someone wants a
long private link that owes nothing to an ISP.

## The constraint that matters

**Part 97.113(a)(4) prohibits "messages encoded for the purpose of obscuring
their meaning."** AREDN's own documentation advises against running software
that encrypts, precisely because it may be read that way.

That is fatal to both stacks this project uses:

- **Reticulum encrypts everything and has no plaintext mode.** No configuration
  makes it Part 97-clean.
- **Meshtastic** encrypts channel payloads by default, and
  `docs/mqtt-broker-vps.md` recommends keeping `mqtt.encryption_enabled` on so a
  broker compromise cannot expose message content. Over AREDN that
  recommendation would have to be reversed.

It also undermines the broker hardening in `docs/mqtt-broker-vps.md`, which is
built on TLS, per-node credentials and topic ACLs.

**So AREDN buys independence from commercial infrastructure and costs
encryption. It cannot give both.**

There is genuine debate — the ARRL has argued encryption for *authentication* is
permissible, and a 2013 FCC petition seeking an emergency-services exception was
dismissed — but "arguable" is a poor foundation for a link anyone depends on.

### We have seen the rule applied, not just written

Node `!8c36d408` (KJ7PJE), decoded from our own radio on 2026-08-18, runs
Meshtastic with `is_licensed: true`. **That flag disables encryption**, and its
NODEINFO and telemetry arrive in plaintext. A licensed operator on the local
mesh is already living with this.

## Licensing, for completeness

Modest, and not the obstacle:

- **Technician class** is sufficient — it grants full privileges above 30 MHz,
  covering every band AREDN uses. General and Extra add HF, which is irrelevant
  here.
- One **35-question multiple-choice exam**, 26 correct to pass. No Morse code
  since 2007. The question pool is published in advance. The Technician pool
  changed on **1 July 2026**, so check study material is current.
- About **$50** all in: roughly $15 to the volunteer examiners plus a $35 FCC
  application fee. Valid **10 years**, renewed free.
- **Node operators must be licensed.** End users of services on the mesh
  generally need not be, provided a licensed control operator supervises. AREDN's
  community treats this as interpretation rather than settled law.

For a three-site link that would mean **a licensed operator at every site**, not
only at ours.

## References

- <https://www.arednmesh.org/>
- <http://docs.arednmesh.org/en/latest/arednServicesGuide/services_overview.html>
- <https://www.ocmesh.net/faqs/use-of-encryption-in-amateur-radio>
- <https://www.fcc.gov/wireless/bureau-divisions/mobility-division/amateur-radio-service/operator-class>
