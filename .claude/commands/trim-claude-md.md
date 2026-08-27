# Trim CLAUDE.md

Bring `CLAUDE.md` back under the 40k character performance limit without losing
anything expensive to rediscover.

## Step 1 — Measure

```bash
wc -c CLAUDE.md
```

Under 30k: report the size and stop. Nothing needs trimming, and cutting a file
that is not too large only loses information.

This project grew `CLAUDE.md` from 4k to 21k in a single session, so measure
rather than assume; it climbs faster than it feels like it should.

## Step 2 — Triage before touching the file

Assign every candidate passage to a destination **before** editing:

| Bucket | Criteria | Action |
|---|---|---|
| **Delete** | One-time setup notes for work already done; narrative of how something was discovered once the finding itself is stated; anything derivable from the code in front of you | Remove |
| **Condense** | A finding that matters but is explained at three times the length it needs | Rewrite to a sentence or two, keeping the *fact* and the *consequence* |
| **Move to README** | Orientation, procedure, or rationale a human arriving cold would want | Add to `README.md` first, then remove |
| **Move to docs/** | Reference too long for README but too valuable to lose | New `docs/<subject>.md`, linked from README |
| **Save to memory** | Cross-project lessons about how to work, not about this repo | Write the memory file first, then remove |

**Never delete without assigning a destination.** Record the disposition in the
Step 5 report.

### Never cut these

This file is mostly hard-won findings. Each of these cost real time and none is
recoverable by reading the code:

- The **variant header is wrong** — SX1262 interrupt is DIO1, and the 1.8 V TCXO
  and DIO2 RF-switch settings the board will not transmit without
- **`ADC_CTRL` polarity is board-revision dependent**, and a voltage on the sense
  line does not prove a battery is fitted
- **MQTT downlink needs the node's own network** — it fails through the phone proxy
- The **CP2102 serial reality** and the ModemManager collision
- The **`grep -q` under `pipefail`** trap, and the `head()` shadowing trap
- **Board GraphQL IDs** — these are not derivable and there is no other copy
- The **no-CI warning**, the **no-attribution rule**, and the **public-repo rule**
- `hopsAway: 0` says nothing about line of sight on this terrain
- The **sync word table** — two of its four rows are the same value, and the
  conclusion that a sync word is not isolation
- **Orange LED is the charger, white is firmware**, and a steady LED is never
  software
- **Both Heltecs report serial `0001`** — by-id collapses them; use by-path and
  confirm by MAC

**A corrected claim is worth more than a new one, so keep the correction
visible.** Where this file records that something was previously wrong — the
`ADC_CTRL` polarity, the node name, the README saying Meshtastic while RNode was
loaded — do not tidy the correction away into a bare statement of fact. The next
session needs to know it was got wrong once.

Prefer condensing prose around a finding over deleting the finding.

## Step 3 — Preserve displaced content first

Write to README, `docs/`, or memory **before** removing anything from
`CLAUDE.md`. If the process is interrupted between the two, the version that
loses nothing is the one where the copy already exists.

**The repository is public.** Moving content to README publishes it. Check for
coordinates, credentials, and channel keys before doing so.

## Step 4 — Edit, then verify

Make targeted edits only. Re-measure:

```bash
wc -c CLAUDE.md
```

Target 30–35k, leaving headroom. If still over 40k, return to Step 2 rather than
cutting deeper into findings.

Sanity-check that the command table still matches the files on disk:

```bash
diff <(grep -oE '^\| `/[a-z-]+' CLAUDE.md | tr -d '|` /' | sort) \
     <(ls -1 .claude/commands/ | sed 's/\.md$//' | sort)
```

## Step 5 — Report and commit

List every section touched and its disposition — deleted, condensed, moved to
README, moved to `docs/`, or saved to memory — with before and after sizes.

Commit on `main` with a `Docs:` prefix, staging only the files this command
changed. No AI attribution.
