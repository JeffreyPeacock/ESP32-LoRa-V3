# Export this session's transcript

Render the Claude Code session log as readable text with secrets masked, using
`scripts/export-transcript.sh`.

`$ARGUMENTS` may contain a date, a session UUID, or an output path. Parse what is
there and ask only for what is genuinely ambiguous.

## Run it

```bash
./scripts/export-transcript.sh
```

That exports the **most recent** session to
`.claude_artifacts/transcripts/YYYY.MM.DD-transcript.txt`, masking as it goes.
The whole of `.claude_artifacts/` is gitignored, and the script refuses to write
anywhere inside the repository that is not ignored.

Useful variants:

```bash
./scripts/export-transcript.sh --list                  # what sessions exist
./scripts/export-transcript.sh --session <uuid>        # a specific one
./scripts/export-transcript.sh --out /tmp/t.txt        # somewhere else
./scripts/export-transcript.sh --no-thinking           # drop reasoning blocks
```

## Masking is the point — do not casually disable it

Session logs collect secrets without anyone intending it. CLI tools echo the
values they set, and config exports contain keys. In this project alone a
transcript has captured a WiFi PSK and a Meshtastic channel URL, and a channel
URL encodes **every channel's pre-shared key**.

Patterns are always masked: channel URLs, WiFi PSKs however they were echoed,
YAML `psk`/`wifiPsk` values, hex PSK arguments, and MQTT passwords.

**Project-specific literals belong in `.claude_artifacts/mask-secrets.txt`**, one
per line. Prefer that over `--secret` on the command line, because a value typed
as an argument lands in shell history *and* in the next transcript.

`--no-mask` exists but writes secrets in clear. Do not use it without the user
asking explicitly, and say plainly what it means when they do.

## After running

Report the output path, the counts the script prints, and the masking summary.

The script verifies its own work: it re-runs the masking patterns against the
finished file and fails if any still match a value. If it reports residuals, do
**not** describe the file as safe — say what matched.

Say plainly that the scan only knows the patterns it was given, and that the file
is worth skimming before it goes anywhere. Automated masking finds what it was
told to look for and nothing else.
