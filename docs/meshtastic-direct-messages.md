# Direct messages in Meshtastic 2.7: the key must arrive first

A direct message is not a channel message with a narrower audience. It is
encrypted to the recipient's public key, and without that key the sender's own
radio refuses to transmit. Everything below was proven on the bench with two
radios rather than read from documentation.

## The failure is local: nothing goes on air

Proven on the bench 2026-09-01. **Broadcasts work immediately; direct messages
do not.** A DM to a node whose public key the sender lacks fails *locally* — the
packet never goes on air, with
`NAK ... PKI_SEND_FAIL_PUBLIC_KEY`. The same NAK appears on the primary channel
and on a private one, so it is not a channel-key problem: **2.7 does not fall
back to channel-PSK encryption for a DM.** Confirmed from the receiving side too,
where `--listen` showed a control broadcast arriving and no trace of the DM.

The key travels in **NodeInfo**. A node that has heard only a text packet knows
the sender's node *number* but not its name or key, so it can be one hop away,
plainly audible, and still unmessagable. NodeInfo goes out on
`device.nodeInfoBroadcastSecs`, **default 10800 s (3 hours)**, so two nodes
flashed together may not be able to message each other for hours. Once exchanged
the DM works first time and is acknowledged.

**A PKI direct message travels on the primary channel regardless of
`--ch-index`.** Sent with `--ch-index 2`, it arrived as `channel: 0`,
`pki_encrypted: True`. Do not read that as a misconfiguration.

`--set-owner` with the values it already holds writes nothing and broadcasts
nothing, so it is not a shortcut for forcing NodeInfo out.

## Why this matters for the multi-site goal

Two sites cannot exchange direct messages until each has heard the other's
NodeInfo. Over a working MQTT bridge that happens on its own, but it is not
instant and it is not something to test once and assume. Broadcasts on a shared
channel work from the first packet and are the right thing to test a new link
with.
