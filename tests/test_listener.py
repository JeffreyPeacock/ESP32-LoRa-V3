#!/usr/bin/env python3
"""Exercise the listener's packet handling without a radio.

The mesh around FTG1 carries almost no text traffic -- a four-minute live
capture recorded none -- so waiting for a real message is not a usable test.
This feeds synthetic packets through the same code path instead and checks the
three decisions that matter: what gets forwarded, what gets recorded but not
forwarded, and what is a duplicate.

    python tests/test_listener.py /tmp/ledger.jsonl etc/secrets/listener.conf

Nothing is sent: the notifier is replaced with one that captures messages.
"""

import json, sys, types
from pathlib import Path
sys.path.insert(0, 'scripts')
import meshtastic_listener as ML

ledger = Path(sys.argv[1])
if ledger.exists(): ledger.unlink()

cfg = Path(sys.argv[2])
settings = ML.Settings(cfg)
settings.ledger = ledger
settings.dm_only = True

sent = []
class FakeNotifier(ML.Notifier):
    def _sendmail(self, msg, label):
        sent.append((label, msg["To"], msg.get("Subject"), msg.get_content()))
        return True
notifier = FakeNotifier(settings)
notifier.s.sms_enabled = True
notifier.s.sms_to = ["5555550123@msg.fi.google.com"]

listener = ML.Listener(settings, notifier)
listener.my_num = 4143681024

# A fake interface exposing just what build_record touches.
iface = types.SimpleNamespace(
    nodes={"!1fa06b14": {"user": {"longName": "Field Unit B", "shortName": "FTG2"},
                         "position": {"latitude": 34.5, "longitude": -112.4},
                         "hopsAway": 1}},
    localNode=types.SimpleNamespace(channels=[
        types.SimpleNamespace(settings=types.SimpleNamespace(name="")),
        types.SimpleNamespace(settings=types.SimpleNamespace(name="mqtt")),
        types.SimpleNamespace(settings=types.SimpleNamespace(name="ftg-priv")),
    ]))

def packet(pid, to, text, ch=2):
    return {"from": 531761940, "fromId": "!1fa06b14", "to": to,
            "toId": "!f6fb8e00" if to == 4143681024 else "^all",
            "id": pid, "rxTime": 1788000000, "rxSnr": -5.25, "rxRssi": -103,
            "hopStart": 3, "hopLimit": 2, "channel": ch, "wantAck": True,
            "decoded": {"portnum": "TEXT_MESSAGE_APP", "text": text}}

print("1. direct message to us")
listener.on_receive(packet(1001, 4143681024, "Reached the trailhead, all good."), iface)
print("2. same packet again (a neighbour rebroadcast)")
listener.on_receive(packet(1001, 4143681024, "Reached the trailhead, all good."), iface)
print("3. broadcast, dm_only is set")
listener.on_receive(packet(1002, 0xFFFFFFFF, "anyone around?"), iface)
print("4. direct message addressed to a different node")
p = packet(1003, 99999999, "not for you"); p["toId"] = "!05f5e0ff"
listener.on_receive(p, iface)
print("5. a position packet, not text")
listener.on_receive({"from": 1, "fromId": "!x", "to": 4143681024, "id": 1004,
                     "decoded": {"portnum": "POSITION_APP"}}, iface)

rows = [json.loads(l) for l in ledger.read_text().splitlines()]
print(f"\nledger rows: {len(rows)}")
for r in rows:
    print(f"  id={r['packet_id']} accepted={r['accepted']:<5} {r['decision']}")
print(f"\nnotifications: {len(sent)}")
for label, to, subj, body in sent:
    print(f"  --- {label} to {to}")
    if subj: print(f"      subject: {subj}")
    for line in body.rstrip().splitlines(): print(f"      {line}")

assert len(rows) == 3, f"expected 3 ledger rows, got {len(rows)}"
assert [r["accepted"] for r in rows] == [True, False, False]
assert len(sent) == 2, f"expected email+sms, got {len(sent)}"
print("\nALL ASSERTIONS PASSED")
