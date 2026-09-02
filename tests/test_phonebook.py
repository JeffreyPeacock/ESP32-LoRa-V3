#!/usr/bin/env python3
"""Check phone-book loading, per-device routing and validation.

    python tests/test_phonebook.py [etc/secrets/listener.conf]

Numbers are printed part-masked: this is a public repository and the file it
reads holds real personal data. Nothing is sent -- no notifier is involved.

Validation is deliberately strict, and that is what most of this checks. A
carrier gateway discards mail for an address it does not recognise without
reporting anything, so a bad number here would look exactly like a message
that was delivered and never arrived.
"""

import json, sys, tempfile, os
sys.path.insert(0, 'scripts')
import meshtastic_listener as ML
from pathlib import Path

def book(data):
    f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False)
    json.dump(data, f); f.close()
    return Path(f.name)

cfg = sys.argv[1] if len(sys.argv) > 1 else 'etc/secrets/listener.conf'
s = ML.Settings(Path(cfg))
print("loaded phone book entries:", len(s.phone_book))
for e in s.phone_book:
    masked = e['phone'][:3] + '***' + e['phone'][-2:]
    print(f"  deviceId={e['deviceId']!r} name={e['name']!r} phone={masked} gw={e['gateway'] or '(default)'}")

print("\nrouting:")
for dev in ('FTG1', 'ftg1', 'FTG2', None):
    got = s.sms_recipients(dev)
    shown = [(a.split('@')[0][:3] + '***@' + a.split('@')[1], n) for a, n in got]
    print(f"  device_id={dev!r:8} -> {shown}")

print("\nvalidation (each must raise):")
for bad, why in [
    ([{"deviceId": "X", "name": "Y"}],                       "missing phone"),
    ([{"deviceId": "X", "name": "Y", "phone": "12345"}],      "too few digits"),
    ([{"deviceId": "", "name": "Y", "phone": "5555550123"}],  "empty deviceId"),
    ({"deviceId": "X"},                                       "not a list"),
]:
    p = book(bad)
    try:
        ML._load_phone_book(p); print(f"  NOT RAISED for {why} <-- BUG")
    except ML.ConfigError as e:
        print(f"  ok  {why:16} -> {str(e).split(':')[-1].strip()[:52]}")
    finally:
        os.unlink(p)

print("\nnormalisation:")
p = book([{"deviceId": "D", "name": "N", "phone": "+1 (720) 555-0123"}])
e = ML._load_phone_book(p)[0]
print(f"  '+1 (720) 555-0123' -> {e['phone'][:3]}***{e['phone'][-2:]} ({len(e['phone'])} digits)")
os.unlink(p)
