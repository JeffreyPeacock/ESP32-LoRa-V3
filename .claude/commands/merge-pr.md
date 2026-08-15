# Merge a PR and close out its tickets

Verify, squash-merge, and do the board housekeeping.

## Determine the PR

Use the number in `$ARGUMENTS`. Otherwise infer from the current branch:

```bash
gh pr view --json number,title,body,statusCheckRollup,closingIssuesReferences
```

If no PR is found, report and stop.

## Step 1 — Verify

**This repository has no CI.** `statusCheckRollup` will normally be empty, and an empty rollup is
**not** evidence of anything. Do not report "all checks passed" when there were no checks.

So verification is local, and you must actually run it — not assume the authoring session did:

```bash
git fetch origin && git checkout <branch> && git pull --ff-only
shellcheck -x scripts/*.sh scripts/lib/*.sh    # must produce NO output
pio run                                        # must end in [SUCCESS]
```

If the PR touches firmware or scripts that drive the board, and the board is attached, also:

```bash
./scripts/heltec-dev.sh check
```

If any gate fails, report and stop. Do not merge.

If a check *is* present and pending or failed, report and stop.

## Step 2 — Squash and merge

```bash
gh pr merge <PR> --repo JeffreyPeacock/ESP32-LoRa-V3 --squash --delete-branch
```

If the merge fails, report and stop — do not continue to housekeeping.

## Step 3 — Update local main

```bash
git checkout main && git pull --ff-only
```

## Step 4 — Identify the closed issues

Read `closingIssuesReferences` from the PR JSON, and also parse the title and body for `closes` /
`fixes` / `resolves` followed by `#<number>`. Collect the unique set.

## Step 5 — Move each closed issue to Completed

```bash
ITEM=$(gh api graphql -f query='
{ repository(owner:"JeffreyPeacock", name:"ESP32-LoRa-V3") {
    issue(number:<N>){ projectItems(first:5){ nodes{ id project{ number } } } } } }' \
  --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number==10) | .id')

gh api graphql -f query='mutation {
  updateProjectV2ItemFieldValue(input:{
    projectId:"PVT_kwHOAdChXs4BgeW5" itemId:"'"$ITEM"'"
    fieldId:"PVTSSF_lAHOAdChXs4BgeW5zhfGh7Y"
    value:{ singleSelectOptionId:"5241f608" } }){ projectV2Item{ id } } }'
```

If an issue is not on the board, note it and continue.

## Step 6 — Update CLAUDE.md if a durable fact changed

Only if the merge changed something that would mislead a future session: a pin definition, a radio
setting, the toolchain layout, a shell convention, or a hardware finding. Routine fixes need no doc
change.

If it did, commit that separately on `main` with a `Docs:` prefix. No AI attribution.

## Step 7 — Report

PR merged, issues moved to Completed, branch deleted, which gates you ran and their **actual**
output, and any CLAUDE.md update made.

State plainly that there was no CI if there was none.
