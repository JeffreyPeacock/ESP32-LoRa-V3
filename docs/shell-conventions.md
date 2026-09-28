# Shell conventions, and the false-zero traps

Every script here must pass `shellcheck -x` with no output. The rules below are
the ones that cost real time; the two that bite hardest stay in `CLAUDE.md`
because a session needs them before it writes a line of shell.

## A zero from a line-based check usually means the check is broken

This is the global prove-the-detector rule in its commonest local form: **match
something known present before trusting a zero.** Four variants cost real time
on 2026-09-25, each looking exactly like an absent finding:

- `cmd | sed` under `||` reports **sed's** exit status, so the fallback never
  fires. The same applies to any pipeline ending in `head`, which silently
  discards the upstream status.
- `\|` inside `grep -E` matches a **literal pipe**, not alternation.
- A phrase wrapped across two lines is invisible to line-based `grep`, so
  **flatten whitespace before matching prose.**
- `awk 'length>80'` counts **bytes**, so em-dashes and `−` produce false
  over-length reports. Count characters in Python instead.

## Sampling a long-running producer under `timeout`

`mosquitto_sub` block-buffers whenever its stdout is not a tty. Under `timeout`
it is killed before the buffer flushes, so it prints **nothing at all** — no
partial line, no error — which is indistinguishable from a subscription that
matched nothing. Two samples were lost to this on 2026-09-25.

**Redirecting to a file does not fix it**, which this project believed for a
day: a file is not a tty either, so the stream is still block-buffered and
SIGTERM discards it. A third sample was lost that way on 2026-09-26. Use `stdbuf
-oL`, and prefer the producer's own clean-exit timeout where it has one, such as
`mosquitto_sub -W <secs>`, because a normal exit flushes.

## Script-specific conventions

- Every subcommand is **idempotent** — re-running changes nothing already in the
  desired state, and the udev rule is rewritten only when its content differs.
- `heltec-setup.sh` escalates **per command** through a `SUDO` array rather than
  re-execing under sudo, so `check` never prompts for a password.
- `heltec-dev.sh` **refuses to run as root**: PlatformIO as root leaves
  root-owned files in `~/.platformio` and `.pio` that break the next build.
- `as-owner.sh` switches the active `gh` account, runs one command, and restores
  the previous account from a trap that also fires on INT and TERM. It verifies
  the switch by re-reading the account rather than trusting an exit status.

## pyenv cannot be reached through shell startup files

`runuser -l` and `su -` give a **non-interactive** login shell, and Ubuntu's
`~/.bashrc` returns on its first line for those, so `pyenv init` never runs.
Resolve interpreters directly by path. `resolve_venv_bin()` accepts four
layouts, so pyenv is this machine's choice and not a project requirement — do
not reintroduce a hard-coded `~/.pyenv/versions/...` path.
