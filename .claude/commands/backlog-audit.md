# Audit the backlog — the board is the source of truth

Audit the open issues on the **LoRa Wide-Area Mesh** board and groom them: check priorities against
the rubric, catch tickets already done, promote what is genuinely next, and flag hygiene problems.

**This command never edits `CLAUDE.md` or `README.md`.** Ticket state does not live in docs.

## Board config

Project **#10**, owner `JeffreyPeacock` (a **user** — GraphQL uses `user(login:)`).
Project `PVT_kwHOAdChXs4BgeW5` · Status field `PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y` —
Backlog `fc0746ee`, Prioritized `7db529ed`, Ready `0559bd80`, In Progress `082c573d`,
Completed `5241f608`. Priority field `PVTSSF_lAHOAdChXs4BgeW5zhfGh_A` —
p1 `768405dd`, p2 `bded9378`, p3 `baa61257`, p4 `90f2d0b0`, p5 `77dadab6`.

> Priority is a **board field**, not a label. A ticket with no priority set is a triage failure, not
> a p3.

## Step 1 — Pull the board

One call gets everything; the board is a dozen items.

```bash
gh project item-list 10 --owner JeffreyPeacock --format json \
  --jq '.items[] | {n: .content.number, title, status, priority,
                    labels: .content.labels, milestone: .content.milestone}'
```

Cross-reference repo state where needed:

```bash
gh issue list --repo JeffreyPeacock/ESP32-LoRa-V3 --state open --limit 100 \
  --json number,title,labels,milestone,createdAt
```

## Step 2 — Checks (read-only)

**1. Priority set and defensible.** Every open item has exactly one priority. Flag anything unset.
Flag mismatches against the rubric: p1 means "the next step cannot happen without it" — on this
project that is a very short list. Flag p1 inflation specifically.

**2. Milestone correct.** `Solo bring-up` = verifiable with only the FLG board. `Multi-site link` =
needs an operator at SJC or SNA, or spans sites. The test is **verifiability, not topic** — this is
the classification most likely to be wrong, because it is tempting to file by subject matter.

**3. Already done.** Find open tickets whose work has landed. Check merged PRs and recent commits:
```bash
gh pr list --repo JeffreyPeacock/ESP32-LoRa-V3 --state merged --limit 20 \
  --json number,title,closingIssuesReferences
git log --oneline -30
```
Also check for work completed **on the bench but never ticketed off** — this project does a lot of
work interactively, so a ticket can be genuinely finished with no commit to prove it. Flag these for
a human glance; never auto-close.

**4. Labels present.** Every open issue carries at least one topical label
(`hardware` `meshtastic` `mqtt` `reticulum` `rf` `coordination` `decision`). Flag bare issues.

**5. Blocked work parked correctly.** Anything labelled `coordination` sitting in **Ready** is
probably mis-staged — it cannot be worked solo. Flag it for demotion to Prioritized.

**6. Stale assumptions.** This project's direction has moved (LoRaWAN → Meshtastic → Reticulum as the
likely end state). Flag any ticket whose body assumes a superseded approach, and say what changed.
This matters more here than duplicate-detection does.

## Step 3 — Present findings and confirm (one pause)

Report grouped by check, each with issue numbers and the proposed action. **List the exact board
mutations** Step 4 would make. Pause for confirmation before mutating anything.

Read-only flags needing a human decision — close candidates, priority disputes, stale assumptions —
are reported, never auto-applied.

## Step 4 — Apply (only after confirmation)

Item-ID lookup per issue, then mutate:

```bash
ITEM=$(gh api graphql -f query='
{ repository(owner:"JeffreyPeacock", name:"ESP32-LoRa-V3") {
    issue(number:<N>){ projectItems(first:5){ nodes{ id project{ number } } } } } }' \
  --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number==10) | .id')

gh api graphql -f query='mutation {
  updateProjectV2ItemFieldValue(input:{
    projectId:"PVT_kwHOAdChXs4BgeW5" itemId:"'"$ITEM"'"
    fieldId:"<field-id>" value:{ singleSelectOptionId:"<option-id>" } }){ projectV2Item{ id } } }'
```

Labels and milestones via `gh issue edit`. **Never close an issue automatically.**

## Step 5 — Report

Issues audited; flags raised by check with numbers; mutations applied; and what is left for a human
decision. The board — not any document — is left as the accurate picture.
