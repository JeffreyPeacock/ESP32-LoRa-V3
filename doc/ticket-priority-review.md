# Ticket Quick View

The [LoRa Wide-Area Mesh board](https://github.com/users/JeffreyPeacock/projects/10) holds the
authoritative detail. This is the at-a-glance ordering the board does not give cleanly, plus a Note
column that is analysis rather than board data.

**Snapshot:** 2026-08-15 17:19 MST · 10 open · 5 Backlog · 3 Prioritized · 2 Ready

|  Pri   | #  |    Status   | Milestone | Title | Note |
|:------:|:--:|:-----------:|:---------:|-------|------|
| **p1** | 3  |    Ready    |    Solo   | Survey: is anyone else on the air within radio range? | The one unknown needing nobody else: is there a mesh within reach of FLG? A definite no is as useful as a yes. |
| **p1** | 7  | Prioritized |    Solo   | Prove the internet-to-mesh injection path against a local broker | Proves the mechanism every remote link depends on, using only FLG. Needs a local mosquitto — the public broker restricts JSON downlink. |
| **p2** | 4  |    Ready    |    Solo   | Pair the phone over BLE | Confirms the phone leg on its own. WiFi and BLE are mutually exclusive on ESP32, so use MQTT proxy mode to keep both. |
| **p2** | 5  | Prioritized |    Solo   | Enable the MQTT bridge via phone proxy | Depends on #4. Uplinking the default channel publishes position and telemetry publicly. |
| **p2** | 6  | Prioritized |    Solo   | Observe our own traffic arriving at the broker | Depends on #5. Proves radio → BLE → phone → internet → broker, every link but the far end. |
| **p2** | 8  |   Backlog   |    Solo   | Evaluate Reticulum / RNode on the same board | The likely end state: routes between networks and holds messages for offline nodes. Export the Meshtastic config first — reflashing this board with RNode is known to be awkward. |
| **p3** | 9  |   Backlog   |   Multi   | Prepare the handoff packet for the SJC operator | Preparing it is solo; delivering it is not. Send --ch-add-url, never --seturl, which replaces all their channels. |
| **p3** | 10 |   Backlog   |   Multi   | Decide the production backbone and broker | Public broker is the fast start. Move to our own if traffic must reach past the far gateway into the local mesh, or for JSON injection. |
| **p4** | 11 |   Backlog   |    Solo   | Calibrate VBAT_DIVIDER against a meter | 4.9 is Heltec's figure, never verified here. Needs a pack and a meter; check polarity against the silkscreen first. |
| **p5** | 12 |   Backlog   |   Multi   | Bring SNA online | Deferred until FLG-to-SJC works. The same handoff packet applies. |

## Tally

| Priority | p1 | p2 | p3 | p4 | p5 | — | Total |
|:--------:|:--:|:--:|:--:|:--:|:--:|:-:|:-----:|
|   Open   | 2  | 4  | 2  | 1  | 1  | 0 |   10  |

&nbsp;

**Legend** — what each priority means:

| Pri | Meaning |  | Pri | Meaning |
|:---:|---------|---|:---:|---------|
| **p1** | Blocks everything downstream, or the radio is unusable until it is done |  | **p4** | Minor, cosmetic, or a convenience |
| **p2** | Needed for the current milestone; no acceptable workaround |  | **p5** | Speculative, deferred, or waiting on something far off |
| **p3** | Real work, schedulable; a workaround or deferral exists |  |  |  |

&nbsp;

**Milestone** — `Solo` is completable *and verifiable* with only the FLG board. `Multi` needs an
operator at SJC or SNA. The test is verifiability, not subject matter.

## Refresh

```bash
gh project item-list 10 --owner JeffreyPeacock --format json \
  --jq '.items[]
        | select(.status != "Completed")
        | [(.priority // "zz"), (.content.number|tostring), .status,
           (if (.milestone.title // "") == "Solo bring-up" then "Solo"
            elif (.milestone.title // "") == "Multi-site link" then "Multi"
            else "—" end),
           .content.title]
        | @tsv' \
  | LC_ALL=C sort -t$'\t' -k1,1 -k2,2n
```

Use `/priority-review` — it preserves the Note column across rebuilds, which this raw query cannot.
Note `.content.title`, not `.title`: the item-level title is a stale snapshot from when the item was
created.
