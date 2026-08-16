# File a new issue and put it on the board

Create a GitHub issue in `JeffreyPeacock/ESP32-LoRa-V3` and add it to the **LoRa Wide-Area Mesh**
project board.

Parse as much as possible from `$ARGUMENTS` (free-form text is fine — title, area, priority, notes).
Only ask for what is genuinely missing.

## Board config

- Repo: `JeffreyPeacock/ESP32-LoRa-V3` · Project: **#10**, owner `JeffreyPeacock` (a **user**, not an
  org — GraphQL uses `user(login:)`, and `gh project` needs `--owner JeffreyPeacock`)
- Project ID `PVT_kwHOAdChXs4BgeW5`
- **Status** field `PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y` — Backlog `fc0746ee`, Prioritized `7db529ed`,
  Ready `0559bd80`, In Progress `082c573d`, Completed `5241f608`
- **Priority** field `PVTSSF_lAHOAdChXs4BgeW5zhfGh_A` — p1 `768405dd`, p2 `bded9378`, p3 `baa61257`,
  p4 `90f2d0b0`, p5 `77dadab6`

> **Priority is a board field here, not a label.** Do not create `priority:pN` labels.

## Labels

| Label | Use for |
|---|---|
| `hardware` | Board, antenna, power, pins, soldering, calibration |
| `meshtastic` | Meshtastic firmware and configuration |
| `mqtt` | Broker, bridging, uplink/downlink, injection |
| `reticulum` | Reticulum / RNode / LXMF |
| `rf` | On-air behaviour, range, survey, antennas in use |
| `coordination` | Depends on an operator at another site |
| `decision` | An open choice still to be settled |

More than one is fine. If nothing fits, propose a new label rather than forcing a bad one.

## Milestones

| Milestone | Criterion |
|---|---|
| `Solo bring-up` | Completable **and verifiable** with only the FTG1 board |
| `Multi-site link` | Needs an operator at another site, or spans sites |

The test is verifiability, not topic. Evaluating Reticulum is solo; preparing a handoff packet
for SJC is not.

## Priority rubric

| Pri | Meaning |
|---|---|
| **p1** | Blocks everything downstream, or the radio is unusable until it is done |
| **p2** | Needed for the current milestone; no acceptable workaround |
| **p3** | Real work, schedulable; a workaround or deferral exists |
| **p4** | Minor, cosmetic, or a convenience |
| **p5** | Speculative, deferred, or dependent on something far off |

Do not inflate p1. On this project p1 means "the next step cannot happen without it".

## Steps

1. **Confirm the parse in one line** — title, labels, milestone, priority, and a sentence of body.
   If something critical is missing, ask. Otherwise proceed without waiting.

2. **Create the issue.** The body should say what the problem or task is, why it matters, and any
   acceptance criteria. Where a command is known, put the actual command in a fenced block — these
   tickets are meant to be executable, not just descriptive.
   ```bash
   gh issue create --repo JeffreyPeacock/ESP32-LoRa-V3 \
     --title "<title>" --body "<body>" \
     --label "<label>[,<label>]" --milestone "<milestone>"
   ```

3. **Add it to the board.**
   ```bash
   gh project item-add 10 --owner JeffreyPeacock --url <issue-url>
   ```

4. **Get the item ID for this issue specifically.** Retry once after a few seconds if empty —
   attachment lags briefly.
   ```bash
   gh api graphql -f query='
   { repository(owner:"JeffreyPeacock", name:"ESP32-LoRa-V3") {
       issue(number: <N>) { projectItems(first:5){ nodes{ id project{ number } } } } } }' \
     --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number==10) | .id'
   ```

5. **Set Status = Backlog and Priority.** Two mutations, same shape:
   ```bash
   gh api graphql -f query='mutation {
     updateProjectV2ItemFieldValue(input:{
       projectId:"PVT_kwHOAdChXs4BgeW5" itemId:"<item-id>"
       fieldId:"PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y"
       value:{ singleSelectOptionId:"fc0746ee" } }){ projectV2Item{ id } } }'
   ```
   Repeat with `fieldId:"PVTSSF_lAHOAdChXs4BgeW5zhfGh_A"` and the priority option ID.

6. **Report:** issue number and URL, labels, milestone, priority, and confirmation it is on the board
   in Backlog. If you set a priority the user did not specify, say so plainly so they can correct it.
