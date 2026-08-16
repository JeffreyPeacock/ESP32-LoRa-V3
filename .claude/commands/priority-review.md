# Rebuild the ticket Quick View

Regenerate `doc/ticket-priority-review.md` — a priority-ordered, at-a-glance table of the open
tickets, meant to be read in an open editor tab beside the code.

The board holds the authoritative detail. This doc exists for two things the board does not give:
**ordering by priority in one screen**, and the **Note** column, which is analysis rather than board
data. Preserving those Notes across rebuilds is the whole point of this command.

`$ARGUMENTS` may give an alternate output path; it defaults to `doc/ticket-priority-review.md`.

## Config

- Repo `JeffreyPeacock/ESP32-LoRa-V3` · Project **#10**, owner `JeffreyPeacock` (a **user**)
- **Priority and Status are board fields**, not labels — both come straight from `item-list`
- Milestone comes from the issue: **Solo bring-up** vs **Multi-site link**

## Three traps in the board JSON

Get these wrong and the table is quietly wrong rather than obviously broken.

1. **Use `.content.title`, never `.title`.** The item-level `.title` is a stale snapshot from when
   the item was created — items converted from draft issues, or renamed since, still carry the old
   text. `.content.title` is live.
2. **`labels` and `milestone` are top-level on the item**, not under `.content`.
3. **`priority` is absent, not null, when unset.** `// "—"` handles it; an unprioritised open ticket
   is a triage failure and must be visible as `—`, not silently sorted as p3.

## Step 1 — Pull the board

One call is complete — this board holds about a dozen items.

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

`zz` sorts unprioritised tickets last; render them as `—`. If nothing comes back, report "no open
tickets" and stop.

## Step 2 — Preserve the human Notes

If the file already exists, read it and extract the **Note** column keyed by issue number. In the
rebuilt table:

- **Reuse each existing Note verbatim** for any ticket still open. Never reword or regenerate a
  human-written Note.
- Leave the Note **blank** for tickets new since the last rebuild.
- After writing the file, offer to draft Notes for the blank ones — one short line each, saying why
  the ticket matters or what it blocks. Do not write them silently.

A Note is the one column that cannot be recovered from the board. Losing one is the only way this
command can do real damage.

## Step 3 — Write the file

Structure:

- `# Ticket Quick View` and a one-line intro naming the board as authoritative.
- `**Snapshot:** <YYYY-MM-DD HH:MM TZ> · <N> open · <status mix>` — capture with
  `date +'%Y-%m-%d %H:%M %Z'`. **Local time, and the time as well as the date**, so successive
  same-day rebuilds are distinguishable.
- The table: `Pri | # | Status | Milestone | Title | Note`. Bold the `pN`. Render unprioritised as
  `—`.
- A `## Tally` section: counts per priority, then a `&nbsp;` spacer line, then the legend. Plain
  blank lines collapse in most renderers; `&nbsp;` gives real vertical space.
- A `## Refresh` section embedding the Step 1 command, so the doc regenerates itself.

### Formatting rules that matter for an at-a-glance doc

- **The `#` column is a bare number — never a markdown link.** A linked cell carries ~60 characters
  of URL, blows out the column, squeezes `Status` until "Prioritized" wraps, and makes renderers
  shrink the whole table. Issue numbers *inside* a Note may be written `#7`.
- **Centre `Pri`, `#`, `Status` and `Milestone`** with alignment colons — they hold short
  fixed-width values. `Title` and `Note` stay left-aligned and ragged; padding them would make every
  line hundreds of characters wide.
- **Size the narrow columns to their actual widest cell.** `Status` is the one that bites:
  `Prioritized` and `In Progress` are 11 characters, so an 8-dash separator renders malformed.
  Measure rather than assume:

  ```bash
  python3 - <<'PY'
  body = open('doc/ticket-priority-review.md').read().split('## Tally')[0]
  rows = [l for l in body.split('\n') if l.startswith('|')]
  cols = zip(*[[len(c.strip()) for c in r.strip('|').split('|')] for r in rows])
  print(dict(zip(['Pri','#','Status','Milestone','Title','Note'], (max(c) for c in cols))))
  PY
  ```

## Step 4 — Report and commit

Report the path written, the count per priority tier, and explicitly list **new tickets with blank
Notes** and any **unprioritised** ones, so the user knows what needs annotating or triage.

Then commit the doc on `main` with a `Docs:` prefix. Unlike the multi-developer project this command
was adapted from, the Quick View here is a tracked artefact: it is the only place the Notes live, it
is worth reading in a diff, and another operator picking up this repo benefits from it. There is no
risk of clobbering someone else's in-flight notes on a solo repo.

Do not commit unrelated changes alongside it.
