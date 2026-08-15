# Drain the Ready column

Work through every issue sitting in **Ready** on the LoRa Wide-Area Mesh board, in order, until the
column is empty or a ticket blocks.

## Board config

Project **#10**, owner `JeffreyPeacock` (a **user** — GraphQL uses `user(login:)`).
Project `PVT_kwHOAdChXs4BgeW5` · Status field `PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y` —
Backlog `fc0746ee`, Prioritized `7db529ed`, Ready `0559bd80`, In Progress `082c573d`,
Completed `5241f608`. Priority field `PVTSSF_lAHOAdChXs4BgeW5zhfGh_A`.

## Step 1 — Enumerate the Ready queue, in priority order

The board is small (a dozen items), so a single `item-list` is cheap and complete — no paging
workarounds needed. Filter and sort locally:

```bash
gh project item-list 10 --owner JeffreyPeacock --format json \
  --jq '.items[] | select(.status=="Ready")
        | [(.priority // "p9"), (.content.number|tostring), .title] | @tsv' \
  | LC_ALL=C sort -t$'\t' -k1,1 -k2,2n
```

If empty, report "Ready queue is empty" and stop.

## Step 2 — Order the work, and say so before starting

Unlike a software backlog, the ordering constraint here is usually **physical, not code-level**:

- **One board, one firmware.** FLG can run Meshtastic or RNode or the PlatformIO diagnostic, never
  two at once. Tickets that require different firmware cannot be interleaved — group them by firmware
  and do all of one before reflashing.
- **Some tickets need the radio listening for a long time.** A survey ticket is not a five-minute
  task; sequence it so it can run while you do desk work.
- **Some tickets are pure desk work** (docs, decisions, script changes) and need no board at all.
  These can be done any time and are good filler.

Present the ordered plan with the reason for the order, and **pause once for confirmation.** After
approval, run through the whole plan without pausing between tickets.

## Step 3 — For each ticket, in order

1. Move it to **In Progress** (`082c573d`) — item-ID lookup as in `/fix-ticket` Step 0.
2. Work it. For anything beyond a one-line change, follow `/fix-ticket <N>` rather than improvising.
3. Gate locally — whichever apply:
   ```bash
   shellcheck -x scripts/*.sh scripts/lib/*.sh
   pio run
   ./scripts/heltec-dev.sh check
   ```
4. Commit, PR, and merge via `/merge-pr`, which moves the ticket to **Completed**.

Documentation-only tickets may go straight to `main`; say which you chose.

## Step 4 — When a ticket blocks

A ticket is blocked, not failed, when it needs something you cannot supply: hardware that is not
attached, a second radio, an operator at SJC or SNA, or a decision only the user can make.

Do not fake progress and do not guess at hardware results. Instead:

1. Comment on the issue describing exactly what was attempted and what it is waiting on.
2. Move it back to **Prioritized** (`7db529ed`) — not Backlog; it was Ready for a reason.
3. Continue with the next ticket.

## Step 5 — Report

Tickets completed (number → PR), tickets blocked (number → what they wait on), the firmware the board
is left running, and the final state of the Ready column.

**State the firmware explicitly.** Leaving FLG on a different firmware than it started on, without
saying so, is the single most confusing outcome of a long run.
