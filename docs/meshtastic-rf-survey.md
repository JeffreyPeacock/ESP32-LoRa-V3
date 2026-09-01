# The RF environment around FTG1

Survey detail from #3 and the sessions after it, moved out of `CLAUDE.md` to
keep that file to things a session must know before touching the hardware. The
conclusions stayed there; the evidence is here.

**FTG1 does not currently run Meshtastic** — it runs RNode (#8). This describes
what was measured while it did, and it is what to re-read before reflashing.

## Is anyone else on the air? Yes

Surveyed 2026-08-15 on the stock LongFast channel with the default key.

- **14 nodes** entered the NodeDB within ~35 minutes of setting the region;
  the ledger has since reached **108**.
- **25 packets from 11 distinct senders** in a single 5-minute capture.
- Typical **SNR −5 to −6 dB, RSSI ≈ −97 dBm**; the best peer sat at **+0.75 dB**.
- Hop spread: 1 node at 0 hops, 2 at 1, 5 at 2, 3 at 3.

This is why link behaviour never had to wait on SJC — real RF peers exist to
test against.

### Peers worth reusing as test targets

| Node | Hops | Note |
|---|---|---|
| `!efa18420` | 0 | Direct neighbour. Busiest sender. |
| `!fe716141` (`MRC`) | 0 | Direct, SNR −11 dB |
| `!9c594d28` (`FLG1`) | 1 | Heltec Mesh Pocket, ~1.4 km |
| `!085e15cb` (`Eldn`) | 0 | Elden-Rptr-1-Mesh — the relay everything leaves town through |
| `!1fa06b14` (`tr`) | 1 | ROUTER 100 km WSW; the next hop after Eldn toward Prescott |

## The path off the Flagstaff bowl is two routers, not one

Traceroute to a Prescott-area node:

```
towards: FTG1 --> !085e15cb (1.0dB) --> !1fa06b14 (-5.75dB) --> !b03b38dc (4.5dB)
back:    !b03b38dc --> !1fa06b14 (-2.75dB) --> !085e15cb (-12.25dB) --> FTG1
```

`Eldn` does not see Prescott. It spans **103.7 km SW to `!1fa06b14`**, which
serves the Prescott area. Do not attribute the whole southwest reach to one node
— an earlier session did exactly that and was wrong.

## Routing is asymmetric, and that is normal

```
towards:  !f6fb8e00 --> efa18420 (-15.5dB)
back:     efa18420 --> 085e15cb (-3.5dB) --> !f6fb8e00 (-1.0dB)
```

Worth remembering when a one-way test looks like a failure.

## The Eldn link is diffraction

Eldn sits on the **north** side of Mt. Elden at 2705 m; FTG1 is on the south side
at 2103 m. The summit (2835 m) lies 58% along the 4.64 km path and stands **384 m
above the line of sight — twenty times the first Fresnel radius**. Deeply
obstructed, and yet a reliable 0-hop link at ~0 dB SNR.

The conclusion is in `CLAUDE.md` because it generalises: on this terrain,
`hopsAway: 0` says nothing about line of sight.

## The node clock lies until it is set

FTG1 has no GPS and no battery-backed RTC. With no time source it seeds from the
**firmware build epoch**, so `--nodes` renders live traffic as "1 month ago".
Our own node reads the same way, which is the giveaway.

```bash
meshtastic --set-time            # host clock; verified skew 0.00 h
```

**It does not survive a power cycle.** Two things set it automatically, so this
is mostly a bench chore: the phone app sets it over BLE, and mesh peers share
time with each other. Set it by hand when working over serial with no phone
attached, and again after any reboot.

Until it is set, trust relative ordering rather than dates, and use a live
capture when recency matters.

## Nobody was actually messaging

A 13-hour capture on 2026-08-18/19 logged **1,576 packets and zero text
messages** — telemetry, position and nodeinfo only. Worth knowing before
investing further in the Meshtastic messaging path.
