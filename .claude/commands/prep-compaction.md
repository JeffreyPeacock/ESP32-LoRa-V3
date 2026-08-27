# Prepare this session's work for compaction

Fold what was learned into the documents before the context that produced it is
gone. Follow the steps in order.

The risk this addresses is specific: on this project the valuable output is often
a **finding** rather than a code change — a polarity that is revision-dependent, a
transport that cannot do downlink, a reading that does not mean what it says.
Those live only in the conversation until someone writes them down.

## Step 1 — What actually happened

```bash
git log --oneline -20
gh issue list --repo JeffreyPeacock/ESP32-LoRa-V3 --state all --limit 15 \
  --json number,title,state --jq '.[] | "#\(.number) [\(.state)] \(.title)"'
```

Separate three things, because they are documented differently:

- **Findings** — something is true that we did not know. Goes in `CLAUDE.md`.
- **State changes** — the radio's configuration changed. Goes in the README table.
- **Narrative** — how we got there. Belongs in commit messages and issue
  comments, not in living documents.

## Step 2 — Update CLAUDE.md with findings only

Targeted edits. Do not rewrite sections that did not change.

**Look hardest for statements that are now wrong.** This is where the real damage
accumulates: a section asserting `ADC_CTRL` must be driven LOW, or that the node
name was deliberately left at factory, is worse than no section, because a later
session will act on it. Correcting a stale claim outranks adding a new one.

Watch the size — 40k is the limit, and this file grows quickly. Use
`/trim-claude-md` if it is over 30k.

## Step 3 — Update the README configuration table

The radio's live state is in `README.md` under FTG1 configuration. If the session
changed region, channels, MQTT, WiFi, position or identity, the table is now
lying. Include the ticket that made each change in the "Set by" column.

The device is authoritative — read it rather than reconstructing from memory.
**Ask the firmware that is actually loaded**, which is not always Meshtastic:

```bash
./scripts/heltec-dev.sh raw          # which firmware is on the board at all
rnodeconf -i <port>                  # if RNode
meshtastic --port <port> --info      # if Meshtastic
rnstatus                             # Reticulum interfaces, if rnsd is running
```

**Confirm which board you are addressing before quoting anything from it.** Two
Heltecs are attached and both report CP2102 serial `0001`; `esptool --port <dev>
chip-id` and the MAC are the only identity. The configs use
`/dev/serial/by-path/` for the same reason.

## Step 4 — Regenerate what is generated

Do not hand-edit these:

```bash
./scripts/peers-report.sh          # if the radio heard anything new
/priority-review                   # if any ticket changed state
```

## Step 5 — Check nothing sensitive is about to be committed

The repository is public and this project has already had a WiFi PSK and a
channel URL land in a session log.

```bash
git grep -niE 'psk|password|wifi_ssid|BEGIN .*PRIVATE KEY' -- . | grep -v '<redacted>'
git status --short --untracked-files=all
```

Confirm no coordinates, no credentials, and that `docs/*.local.md`,
`.claude_artifacts/` and `scripts/local-*.sh` are still ignored.

## Step 6 — Optionally export the transcript

If the session found things worth keeping verbatim:

```bash
./scripts/export-transcript.sh
```

Masking is on by default and it verifies its own output.

## Step 7 — Commit on main

```bash
git branch --show-current      # must be main
```

Stage only what this command changed. `Docs:` prefix. **No AI attribution.**

Write the commit message to explain *why* something is true, not just that it
changed — the commit log is where the narrative belongs, and it is the only place
a future reader can recover the reasoning.

## Step 8 — Report

What was updated, what was deliberately left alone, and — most importantly — any
**stale claim you corrected**, since that is the thing most likely to have misled
someone later.
