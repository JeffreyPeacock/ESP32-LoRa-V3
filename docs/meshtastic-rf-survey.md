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

## The peer ledger, and why a scan is not a record

`peers-report.sh` writes `docs/peers.local.md` and `docs/peers.local.json`,
both excluded by `docs/*.local.*`. It refuses to run unless both are
gitignored, because **coordinates are someone else's location** even though
node IDs are public.

**The NodeDB ages entries out, so a single scan is not a record.** The script
accumulates everything ever seen into the JSON and merges it back each run.
185 entries as of 2026-09-25: 160 then in the NodeDB plus 25 retained from
earlier scans, 101 positioned, 21 within 15 mi.

**There is one ledger, on the workstation.** An earlier note claimed two, one
per host, with pi4's authoritative "because the radio is there". Both halves
were wrong. `~ftg` has no ledger at any depth and no checkout for the script
to write into, so the 155-entry figure came from a run pointed at a file since
gone. The reasoning was void as well: the radio is on WiFi, so **any host on
the LAN can produce the ledger** with `peers-report.sh --host <radio>`, and
which USB socket it occupies decides nothing.

Its main consumer is `~/deployments/prod/bin/seed-meshview-from-peers.py` on
pi4, which fills meshview's node table from the ledger because meshview learns
a name only from a NodeInfo packet. **Seeded rows carry the ledger's
timestamps, not `now()`**, so a node last heard weeks ago stays outside a
narrow map window instead of pretending to be current. Seeding can therefore
grow the database and leave the map showing no more nodes, or fewer.

## Silence is not evidence here — the mesh is slow

Measured 2026-09-25: **one packet every ~140 s** reaches the broker
(0.0077/s, about 668/day). A 60-second watch seeing nothing is the *expected*
result, and even 450 seconds of silence is only about 4% surprising.

**A subscription that matches nothing, a quiet mesh, and a sampler killed
before it flushed all produce the same empty output.** What works is a
comparison that can fail: run the old and the new filter against the broker
**at the same time** and compare counts. Narrowing meshview from `msh/#` to
`msh/US/2/e/#` was confirmed that way, both returning the same 4 messages over
300 s.
