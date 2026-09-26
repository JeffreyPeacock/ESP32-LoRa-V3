# FTG1's fixed position, and what the privacy offset costs

FTG1 has no GPS and broadcasts a **fixed position** set with
`--setlat/--setlon/--setalt`. That position is deliberately not where the radio
is. This document is the reasoning behind that choice, what the published value
has actually revealed over time, and the one place where the offset changes how
you must do engineering work.

**Nothing in this file is a coordinate.** The broadcast value is already public
on the mesh and on meshview; the real location, the offset's magnitude and its
bearing are in `etc/secrets/` and must never reach a tracked file. This
repository is public, so the broadcast coordinate plus the offset would give up
the real location exactly. `CLAUDE.md` states only that an offset exists, and so
does this document.

## Where each value lives

| | |
|---|---|
| `etc/secrets/ftg1-geoloc.txt` | the radio's real approximate location — ground truth, owner-maintained |
| `etc/secrets/ftg1-position.conf` | the broadcast (decoy) coordinate, the device state that goes with it, the measured offset, and the command to re-apply it |
| the radio itself | authoritative for what is being broadcast: `meshtastic --host <ip> --info` |

Both secrets files are mode 600 inside a directory gitignored as a whole.

FTG1 has no GPS. It carries a **fixed position** set with
`--setlat/--setlon/--setalt`, chosen as a nearby public landmark rather than the
operator's address.

**The coordinates are in no tracked file**, because they approximate where the
operator lives and the rule applied to other operators' positions applies to
ours. They *are* recorded now: `etc/secrets/ftg1-position.conf`, gitignored and
mode 600, written 2026-09-25 with the degrees, the protobuf integer form, the
altitude and the command to re-apply them. **This file used to say to read them
off the device with `--info` each time; read the secrets file instead.**

**`position_precision` on channel 0 was 13 until 2026-09-23 and is now 32.** The
old note here said the published position was quantised to roughly km scale. That
is no longer true: the radio now transmits the stored coordinate exactly, to every
map and every node that hears it.

What blunts the disclosure is that **the stored fix is offset from where the
radio actually is, and is a public landmark rather than the operator's
address.**
The offset's size and bearing are recorded **only** in `etc/secrets/`. They must
never appear here: this repository is public and the broadcast coordinate is
public too, so publishing the offset would hand over the real location.

**Correction — this file used to say precision was "blurring a decoy, which
bought nothing".** Half wrong. It did cost accuracy, and that half stands. But
quantisation published an *area* where precision 32 publishes a *point*, and the
cell is several km on a side (below), so dropping to 32 gave up real protection
rather than none. What quantisation never gave was **secrecy** — the grid is
public and deterministic, so anyone who knows it recovers the cell. Area
uncertainty, not a hidden offset.

One ordering consequence: once a position is broadcast a location-hinting **node
name adds little further disclosure**, because the packet is more precise than
the name. The name was chosen assuming no position was being sent.

## Reduced precision is a shared bucket, not a location

**Eight nodes reported the identical latitude `352059392`**, including FTG2 and
six strangers. A coordinate several nodes share is a quantisation cell, not a
place — which is why FTG1 appeared 1.4 km out, on the exact spot FTG2 had
occupied: same bucket, not same field.

The grid was **confirmed, not guessed**: the step is `2^18` in units of 1e-7
degrees (0.0262144°, roughly 2.9 km N–S and 2.4 km E–W at this latitude), and
snapping the stored coordinate to it reproduces `352059392` exactly. That bucket
and the grid are both public, so recording them here discloses nothing.

So **do not read a map position as a measurement** when the sender runs reduced
precision. And **fixing it in the database does not work** — meshview stores
whatever arrives, so a hand-edited row is overwritten by the next position
packet. The only fix is at the radio.

## The offset costs nothing on the air and everything in geometry

**Nothing the radio does is affected.** Meshtastic floods with a hop limit
rather than routing by geography, so a fixed position sets no transmit
parameter, no
neighbour selection and no rebroadcast decision. Free-space loss changes by a
fraction of a dB over any path of interest here.

**But the offset is large compared with the first Fresnel radius at these path
lengths**, so **terrain profiles, line-of-sight checks and antenna siting must
use the real coordinate from `etc/secrets/`**, never the broadcast one. Treat
any existing path analysis as drawn from the broadcast position unless it says
otherwise. `peers-report.sh` reads its origin from the device, so its distances
and its "within 15 mi" count come from the broadcast position too — small
against that threshold, but not zero.

## Why this moved out of CLAUDE.md

`CLAUDE.md` carries what a session needs in its head while working. The
headlines stayed there: where the coordinates live, that precision is now 32 so
the stored value leaves the radio exactly, and that terrain work must use the
real coordinate. The measurement and the reasoning are here because they are
read once and then relied on, not held in mind.
