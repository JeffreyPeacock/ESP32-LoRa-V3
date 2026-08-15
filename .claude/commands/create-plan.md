# Enter planning mode for a task

The task to plan is the argument text passed to this command. If no argument was given, ask what to
plan before proceeding.

## Step 1 — Enter plan mode

Use ToolSearch with query `"select:EnterPlanMode"` to load the tool schema, then call EnterPlanMode.

## Step 2 — Follow the plan mode workflow

Once in plan mode, follow the phased workflow from the plan mode system instructions: understand,
design, review with the user, write the plan file, then call ExitPlanMode for approval.

Treat the argument as the user's planning request — as if they had typed it while already in plan
mode.

## Project note

Much of the uncertainty on this project is **physical or external**, not in the code: whether another
radio is within range, whether an operator at SJC or SNA is reachable, whether a setting the docs
describe actually behaves that way on this board.

A plan that assumes those away is worthless. Where a step depends on an unknown of that kind, say so
in the plan and give the cheapest way to find out — usually a bench observation, not more reading.
Prefer sequencing work so that everything verifiable with only the FLG board happens first.
