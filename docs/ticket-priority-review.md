# Ticket Quick View

The [LoRa Wide-Area Mesh board](https://github.com/users/JeffreyPeacock/projects/10) holds the
authoritative detail. This is the at-a-glance ordering the board does not give cleanly, plus a Note
column that is analysis rather than board data.

**Snapshot:** 2026-09-04 21:30 MST · 10 open · 8 Backlog · 2 In Progress

|  Pri   | #  |    Status   | Milestone | Title | Note |
|:------:|:--:|:-----------:|:---------:|-------|------|
| **p2** | 8  | In Progress |    Solo   | Evaluate Reticulum / RNode on the same board | Paused, not abandoned. Both boards were RNode and are now Meshtastic; `etc/rnode/RESTORE.md` has everything needed to go back. |
| **p2** | 15 | In Progress |    Solo   | Epic: Reticulum — everything provable with one node | Paused with #8. A Pi is a better Reticulum host than a Meshtastic one — `rnsd` wants to run continuously. |
| **p3** | 9  |   Backlog   |   Multi   | Prepare the handoff packet for the SJC operator | #7 established that a remote link needs the far node on its own WiFi/Ethernet, not a phone proxy. Say so in the handoff. |
| **p3** | 10 |   Backlog   |   Multi   | Decide the production backbone and broker | #7 narrowed this: a broker on a private LAN address cannot serve another site. Needs a public host or a VPN. |
| **p3** | 16 |   Backlog   |     —     | Epic: Meshtastic — bring-up, survey, MQTT bridging and what is left | Where the current work belongs. The listener, the two-radio messaging path and the Pi move all sit under this and are not yet itemised as children. |
| **p3** | 17 |   Backlog   |    Solo   | Install Sideband desktop and connect it to FTG1 | Blocked while FTG1 runs Meshtastic; Sideband needs RNode. Reopen with #8. |
| **p5** | 11 |   Backlog   |    Solo   | Calibrate VBAT_DIVIDER against a meter | Blocked by #13 — cannot calibrate a divider that will not connect. Also needs a pack and a meter. |
| **p5** | 12 |   Backlog   |   Multi   | Bring SNA online | Deferred until FTG1-to-SJC works. The same handoff packet applies. |
| **p5** | 13 |   Backlog   |    Solo   | Flash the diagnostic and settle the ADC_CTRL polarity | Testable with no battery: the charger rail gives ~845 mV on the correct polarity and ~0 on the wrong one. Settles a documented-as-fact error. |
| **p5** | 14 |   Backlog   |    Solo   | LoRaWAN gateway to Meshtastic bridge for long-life field sensors | Independent of the multi-site link. LoRaWAN sensors sleep (years on a cell); Meshtastic nodes listen (a day). That asymmetry is the whole argument. |

## Tally

| Priority | p1 | p2 | p3 | p4 | p5 | — | Total |
|:--------:|:--:|:--:|:--:|:--:|:--:|:-:|:-----:|
|   Open   | 0  | 2  | 4  | 0  | 4  | 0 |   10  |

&nbsp;

**Legend** — what each priority means:

| Pri | Meaning |  | Pri | Meaning |
|:---:|---------|---|:---:|---------|
| **p1** | Blocks everything downstream, or the radio is unusable until it is done |  | **p4** | Minor, cosmetic, or a convenience |
| **p2** | Needed for the current milestone; no acceptable workaround |  | **p5** | Speculative, deferred, or waiting on something far off |
| **p3** | Real work, schedulable; a workaround or deferral exists |  |  |  |

&nbsp;

**Milestone** — `Solo` is completable *and verifiable* with only the FTG1 board. `Multi` needs an
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
