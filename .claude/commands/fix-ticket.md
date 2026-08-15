# Work a ticket end to end

Work the issue number given in the argument (e.g. `/fix-ticket 3`). Follow every step in order.

If no argument was given, ask which issue and stop.

## Board config

Project **#10**, owner `JeffreyPeacock` (a **user** — GraphQL uses `user(login:)`).
Project `PVT_kwHOAdChXs4BgeW5` · Status field `PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y` —
Backlog `fc0746ee`, Prioritized `7db529ed`, Ready `0559bd80`, In Progress `082c573d`,
Completed `5241f608`.

## Step 0 — Move the ticket to In Progress

```bash
ITEM=$(gh api graphql -f query='
{ repository(owner:"JeffreyPeacock", name:"ESP32-LoRa-V3") {
    issue(number: <N>) { projectItems(first:5){ nodes{ id project{ number } } } } } }' \
  --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number==10) | .id')

gh api graphql -f query='mutation {
  updateProjectV2ItemFieldValue(input:{
    projectId:"PVT_kwHOAdChXs4BgeW5" itemId:"'"$ITEM"'"
    fieldId:"PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y"
    value:{ singleSelectOptionId:"082c573d" } }){ projectV2Item{ id } } }'
```

If the item is not on the board, warn and continue — the board is bookkeeping; the work is not.

## Step 1 — Read the ticket

```bash
gh issue view <N> --repo JeffreyPeacock/ESP32-LoRa-V3 --json number,title,body,labels,milestone
```

Many tickets on this board carry the exact commands to run in their body. Use them rather than
re-deriving. Identify what "done" means before touching anything, and ask if you are not at 95%
confidence.

**If the ticket is labelled `coordination`, stop and confirm with the user.** That work depends on an
operator at another site who may not be reachable, and the ticket may not be actionable today.

## Step 2 — Decide whether hardware is required

Tickets labelled `hardware`, `rf` or `meshtastic` usually need the board attached.

```bash
./scripts/heltec-dev.sh check
```

If the board is not attached and the ticket needs it, say so and stop rather than guessing at
results. **Never report a hardware outcome that was not observed.**

## Step 3 — Branch from a current main

```bash
git checkout main && git pull --ff-only
git checkout -b <type>/<short-description>
```

Branch prefixes: `fix/`, `feat/`, `docs/`, `chore/`.

Documentation-only or board-only tickets may be committed straight to `main` — say which you chose.

## Step 4 — Read before editing

Read the files involved with the Read tool. `CLAUDE.md` records the hardware and toolchain facts that
are easy to get wrong from memory — check it before changing pin definitions, radio settings, or
anything in `scripts/`.

## Step 5 — Make the smallest change that resolves the ticket

No unrelated refactoring, no drive-by cleanups.

## Step 6 — Gate locally

Whichever apply to what you changed. All must pass.

```bash
shellcheck -x scripts/*.sh scripts/lib/*.sh    # must produce NO output
pio run                                        # must end in [SUCCESS]
./scripts/heltec-dev.sh check                  # if hardware is involved
```

Firmware changes that can be verified on the board should be: `./scripts/heltec-dev.sh flash` and
read the actual serial output. Paste real output into the PR — not what you expect it to say.

## Step 7 — Commit

```bash
git add <specific files>
git commit -m "<Type>: <description> (#<N>)"
```

**No `Co-Authored-By`. No AI attribution of any kind.** This is a standing rule for this repository.

## Step 8 — Push and open a PR

```bash
git push -u origin <branch>
gh pr create --repo JeffreyPeacock/ESP32-LoRa-V3 \
  --title "<Type>: <description> (#<N>)" \
  --body "$(cat <<'EOF'
## Summary
- <what changed and why>

## Verification
- [ ] shellcheck -x clean
- [ ] pio run succeeds
- [ ] <hardware observation, with real serial output if applicable>

Closes #<N>
EOF
)"
```

No generated-with footer.

## Step 9 — Return to main

```bash
git checkout main
```

## Step 10 — Report

Issue number, branch, PR number and URL, which gates were run and their results, and anything left
unverified — particularly anything that needed hardware you did not have. Then hand off to
`/merge-pr <PR>`.

> This repository has **no CI**. There are no status checks to wait on, so the local gates in Step 6
> are the only gates. Do not claim CI passed.
