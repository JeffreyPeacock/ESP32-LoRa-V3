#!/usr/bin/env python3
"""Record and forward Meshtastic messages addressed to this node.

Holds the serial port open, watches for text messages, writes every one it
accepts to a JSON Lines ledger, and forwards it to email and to an SMS gateway.

The radio serves one host at a time. While this runs, `meshtastic --info` and
anything else that opens the port will fail -- stop the listener first.

Configuration is an INI file; see etc/listener.conf.example. The real one holds
a phone number and an email address, so it belongs in etc/secrets/, which is
gitignored as a whole directory.
"""

from __future__ import annotations

import argparse
import configparser
import json
import logging
import os
import signal
import subprocess
import sys
import threading
import time
from collections import deque
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import parseaddr
from pathlib import Path

LOG = logging.getLogger("listener")

BROADCAST_NUM = 0xFFFFFFFF
BROADCAST_IDS = {"^all", "!ffffffff"}

# Meshtastic reuses a 32-bit packet id, and a packet can arrive more than once
# when several neighbours rebroadcast it. Remember enough ids to cover that
# without growing without bound.
SEEN_CAPACITY = 512


class ConfigError(RuntimeError):
    pass


# --- configuration -----------------------------------------------------------


class Settings:
    """Parsed listener.conf. Every lookup is explicit so a typo in the file
    fails at startup rather than silently disabling a notification path."""

    def __init__(self, path: Path):
        parser = configparser.ConfigParser()
        parser.optionxform = str  # keep key case as written
        read = parser.read(path, encoding="utf-8")
        if not read:
            raise ConfigError(f"cannot read config file: {path}")
        self.path = path

        listen = self._section(parser, "listen")
        self.port = listen.get("port", fallback="").strip()
        if not self.port:
            raise ConfigError("[listen] port is required")
        # Which radio this listener speaks for, matched against "deviceId" in
        # the phone book. Left blank, it is taken from the radio's own short
        # name at connect time, so there is one fewer place to get out of step.
        self.device_id = listen.get("device_id", fallback="").strip()
        self.dm_only = listen.getboolean("dm_only", fallback=True)
        self.channel_allowlist = _split_list(listen.get("channels", fallback=""))
        self.ledger = _expand(listen.get("ledger", fallback="etc/secrets/received.jsonl"))
        self.reconnect_secs = listen.getint("reconnect_secs", fallback=15)

        email_s = self._section(parser, "email")
        self.email_enabled = email_s.getboolean("enabled", fallback=False)
        self.email_to = _split_list(email_s.get("to", fallback=""))
        self.email_from = email_s.get("from", fallback="").strip()
        self.email_subject_prefix = email_s.get("subject_prefix", fallback="[FTG1]").strip()
        self.email_subject_template = email_s.get(
            "subject_template", fallback="{prefix} message from {who}"
        ).strip()

        sms = self._section(parser, "sms")
        self.sms_enabled = sms.getboolean("enabled", fallback=False)
        self.sms_to = _split_list(sms.get("to", fallback=""))
        self.sms_from = sms.get("from", fallback="").strip()
        # Recipients can also come from a phone book keyed by device, so that
        # adding a person is a data change rather than a config change, and so
        # a second radio can route somewhere else entirely.
        phones = sms.get("phones_file", fallback="").strip()
        self.phones_file = _expand(phones) if phones else None
        self.sms_gateway = sms.get("gateway", fallback="msg.fi.google.com").strip()
        self.phone_book = _load_phone_book(self.phones_file) if self.phones_file else []
        # Carrier gateways truncate hard and some prepend the subject to the
        # body. Default to no subject and a conservative length.
        self.sms_subject = sms.get("subject", fallback="").strip()
        # str.format template over the ledger fields. {text} is truncated to
        # whatever room the rest of the template leaves.
        self.sms_body_template = sms.get(
            "body_template", fallback="{text} [{from_short} {rx_snr}dB]"
        ).strip()
        self.sms_max_chars = sms.getint("max_chars", fallback=140)
        self.sms_max_per_hour = sms.getint("max_per_hour", fallback=20)

        self.sendmail = _expand(
            self._section(parser, "mail").get("sendmail", fallback="/usr/sbin/sendmail")
        )

        if self.email_enabled and not (
            self.email_to or any(e["email"] for e in self.phone_book)
        ):
            raise ConfigError(
                "[email] enabled but neither 'to' nor any 'email' in the phone book"
            )
        if self.sms_enabled and not (self.sms_to or self.phone_book):
            raise ConfigError(
                "[sms] enabled but neither 'to' nor a non-empty 'phones_file' was given"
            )

    def sms_recipients(self, device_id: str | None) -> list[tuple[str, str]]:
        """Addresses to text for this device, as (address, person) pairs.

        Any literal [sms] to= addresses always apply. Phone-book entries apply
        only when their deviceId matches, so one file can serve several radios.
        """
        out = [(addr, "") for addr in self.sms_to]
        if not device_id:
            if self.phone_book:
                LOG.warning(
                    "phone book has %d entr(ies) but this listener has no device id, "
                    "so none of them can be matched",
                    len(self.phone_book),
                )
            return out
        for entry in self.phone_book:
            if entry["deviceId"].casefold() != device_id.casefold():
                continue
            if not entry.get("enabled", True):
                LOG.info("phone book entry for %s is disabled, skipping", entry["name"])
                continue
            if not entry["phone"]:
                continue
            gateway = entry.get("gateway") or self.sms_gateway
            out.append((f"{entry['phone']}@{gateway}", entry["name"]))
        return out

    def email_recipients(self, device_id: str | None) -> list[tuple[str, str]]:
        """Addresses to mail for this device, as (address, person) pairs.

        Same shape as sms_recipients: literal [email] to= addresses always
        apply, phone-book entries apply only when their deviceId matches.
        """
        out = [(addr, "") for addr in self.email_to]
        if not device_id:
            return out
        for entry in self.phone_book:
            if entry["deviceId"].casefold() != device_id.casefold():
                continue
            if not entry.get("enabled", True) or not entry["email"]:
                continue
            out.append((entry["email"], entry["name"]))
        return out

    @staticmethod
    def _section(parser: configparser.ConfigParser, name: str):
        if not parser.has_section(name):
            parser.add_section(name)
        return parser[name]


def _load_phone_book(path: Path) -> list[dict]:
    """Read the device-to-people routing file.

    Shape is a list of objects; deviceId, name and phone are required, gateway
    and enabled are optional:

        [{"deviceId": "FTG1", "name": "Jeffrey", "phone": "5555550123"}]

    Validation is strict on purpose. A carrier gateway silently discards mail
    for an address it does not recognise, so a typo here would look exactly
    like a delivered message that never arrived.
    """
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"phones_file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"phones_file is not valid JSON ({path}): {exc}") from exc

    if not isinstance(raw, list):
        raise ConfigError(f"phones_file must contain a JSON list, got {type(raw).__name__}")

    entries = []
    for index, item in enumerate(raw):
        where = f"{path} entry {index}"
        if not isinstance(item, dict):
            raise ConfigError(f"{where}: expected an object, got {type(item).__name__}")
        for key in ("deviceId", "name"):
            if not str(item.get(key, "")).strip():
                raise ConfigError(f"{where}: missing or empty {key!r}")

        raw_phone = str(item.get("phone", "")).strip()
        raw_email = str(item.get("email", "")).strip()
        # One or the other is enough: someone may want texts only, or mail
        # only. Neither means the entry can never do anything, which is a
        # mistake rather than a preference.
        if not raw_phone and not raw_email:
            raise ConfigError(f"{where}: needs at least one of 'phone' or 'email'")

        digits = ""
        if raw_phone:
            digits = "".join(ch for ch in raw_phone if ch.isdigit())
            # Accept a leading US country code but store the 10-digit form,
            # which is what the carrier gateways expect.
            if len(digits) == 11 and digits.startswith("1"):
                digits = digits[1:]
            if len(digits) != 10:
                raise ConfigError(
                    f"{where}: {raw_phone!r} is not a 10-digit US number "
                    f"(got {len(digits)} digits)"
                )
        if raw_email and ("@" not in raw_email or raw_email.startswith("@")
                          or raw_email.endswith("@")):
            raise ConfigError(f"{where}: {raw_email!r} does not look like an address")

        entries.append(
            {
                "deviceId": str(item["deviceId"]).strip(),
                "name": str(item["name"]).strip(),
                "phone": digits,
                "email": raw_email,
                "gateway": str(item.get("gateway", "")).strip(),
                "enabled": bool(item.get("enabled", True)),
            }
        )
    return entries


def _split_list(raw: str) -> list[str]:
    return [item.strip() for item in raw.replace("\n", ",").split(",") if item.strip()]


def _expand(raw: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(raw.strip()))).resolve()


# --- outbound ----------------------------------------------------------------


class Notifier:
    """Sends through the local MTA. Postfix on this host relays outbound, so
    both email and the carrier SMS gateway use the same path -- an SMS is just
    a short message to <number>@<gateway>."""

    def __init__(self, settings: Settings, dry_run: bool = False):
        self.s = settings
        self.dry_run = dry_run
        # Set once the radio is open, or from [listen] device_id. Selects which
        # phone-book entries apply.
        self.device_id: str | None = settings.device_id or None
        self._sms_times: deque[float] = deque()

    def _sendmail(self, msg: EmailMessage, label: str) -> bool:
        if self.dry_run:
            LOG.info("dry-run: would send %s to %s", label, msg["To"])
            return True
        # -f sets the envelope sender to match the From header. Without it the
        # envelope carries the invoking unix user, and postfix rewrites the two
        # through smtp_generic_maps independently -- so they arrive as
        # different addresses, which reads as forgery to a spam filter.
        argv = [str(self.s.sendmail), "-t", "-oi"]
        sender = _address_only(msg["From"])
        if sender:
            argv += ["-f", sender]
        try:
            proc = subprocess.run(
                argv,
                input=msg.as_bytes(),
                capture_output=True,
                timeout=60,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            LOG.error("%s failed to hand off to sendmail: %s", label, exc)
            return False
        if proc.returncode != 0:
            LOG.error(
                "%s: sendmail exited %d: %s",
                label,
                proc.returncode,
                proc.stderr.decode("utf-8", "replace").strip(),
            )
            return False
        LOG.info("%s handed to sendmail for %s", label, msg["To"])
        return True

    def email(self, record: dict) -> bool:
        if not self.s.email_enabled:
            return False
        recipients = self.s.email_recipients(self.device_id)
        if not recipients:
            LOG.warning(
                "email enabled but no recipient matched device id %r", self.device_id
            )
            return False

        who = record.get("from_long") or record.get("from_id") or "unknown"
        subject = _render(
            self.s.email_subject_template,
            record,
            prefix=self.s.email_subject_prefix,
            who=who,
        ).strip()
        body = _format_email_body(record)

        any_sent = False
        # One message per recipient, matching the SMS path: a single bad
        # address then cannot suppress delivery to everyone else.
        for address, person in recipients:
            msg = EmailMessage()
            msg["To"] = address
            if self.s.email_from:
                msg["From"] = self.s.email_from
            msg["Subject"] = subject
            msg.set_content(body)
            if self._sendmail(msg, f"email[{person or address}]"):
                any_sent = True
        return any_sent

    def sms(self, record: dict) -> bool:
        if not self.s.sms_enabled:
            return False
        recipients = self.s.sms_recipients(self.device_id)
        if not recipients:
            LOG.warning(
                "SMS enabled but no recipient matched device id %r", self.device_id
            )
            return False

        body = _format_sms_body(record, self.s.sms_max_chars, self.s.sms_body_template)
        any_sent = False
        # One message per recipient rather than one with several addressees:
        # carrier gateways handle a single destination far more predictably,
        # and one bad address then cannot suppress the others.
        for address, person in recipients:
            if not self._sms_budget_ok():
                LOG.warning(
                    "SMS to %s suppressed: more than %d in the last hour",
                    person or address,
                    self.s.sms_max_per_hour,
                )
                continue
            msg = EmailMessage()
            msg["To"] = address
            if self.s.sms_from:
                msg["From"] = self.s.sms_from
            # Left empty by default: several gateways prepend the subject to
            # the body, which spends characters that are already scarce.
            if self.s.sms_subject:
                msg["Subject"] = self.s.sms_subject
            msg.set_content(body)
            if self._sendmail(msg, f"sms[{person or address}]"):
                self._sms_times.append(time.time())
                any_sent = True
        return any_sent

    def _sms_budget_ok(self) -> bool:
        cutoff = time.time() - 3600
        while self._sms_times and self._sms_times[0] < cutoff:
            self._sms_times.popleft()
        return len(self._sms_times) < self.s.sms_max_per_hour


def _address_only(header) -> str:
    """The bare address from a From header, dropping any display name."""
    if not header:
        return ""
    _, address = parseaddr(str(header))
    return address


class _SafeFields(dict):
    """Render a template without crashing on an unknown field.

    A typo in a template should produce a visibly wrong message, not take the
    listener down in the middle of forwarding something.
    """

    def __missing__(self, key):
        LOG.warning("template referenced unknown field %r", key)
        return f"<{key}?>"


def _render(template: str, record: dict, **extra) -> str:
    fields = _SafeFields({k: ("" if v is None else v) for k, v in record.items()})
    fields.update(extra)
    try:
        return template.format_map(fields)
    except (ValueError, IndexError) as exc:
        LOG.error("template %r is malformed (%s); falling back to the raw text", template, exc)
        return str(record.get("text", ""))


def _format_email_body(record: dict) -> str:
    lines = [record.get("text", ""), "", "-- metadata --"]
    for key in (
        "received_at",
        "from_id",
        "from_long",
        "from_short",
        "to_id",
        "channel",
        "channel_name",
        "direct",
        "packet_id",
        "rx_snr",
        "rx_rssi",
        "hops_away",
        "hop_start",
        "hop_limit",
        "portnum",
        "sender_lat",
        "sender_lon",
    ):
        if record.get(key) is not None:
            lines.append(f"{key:14s} {record[key]}")
    return "\n".join(lines) + "\n"


def _format_sms_body(record: dict, limit: int, template: str) -> str:
    """Render the template, truncating {text} rather than the whole message.

    Truncating the finished string would cut off the sender and signal that the
    template deliberately puts at the end, so the overhead is measured first and
    the message text is fitted into what is left.
    """
    overhead = len(_render(template, {**record, "text": ""}))
    room = max(limit - overhead, 1)
    text = str(record.get("text", "") or "")
    if len(text) > room:
        text = text[: max(room - 1, 1)] + "…"
    return _render(template, {**record, "text": text})


# --- packet handling ---------------------------------------------------------


def build_record(packet: dict, interface) -> dict | None:
    """Flatten a Meshtastic packet into the row we keep. Returns None for
    anything that is not a text message."""
    decoded = packet.get("decoded") or {}
    portnum = decoded.get("portnum")
    if portnum != "TEXT_MESSAGE_APP":
        return None
    text = decoded.get("text")
    if text is None:
        payload = decoded.get("payload")
        if isinstance(payload, (bytes, bytearray)):
            text = payload.decode("utf-8", "replace")
    if text is None:
        return None

    from_id = packet.get("fromId")
    to_id = packet.get("toId")
    to_num = packet.get("to")

    node = {}
    if from_id and getattr(interface, "nodes", None):
        node = interface.nodes.get(from_id) or {}
    user = node.get("user") or {}
    position = node.get("position") or {}

    rx_time = packet.get("rxTime")
    record = {
        "received_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "rx_time": (
            datetime.fromtimestamp(rx_time, timezone.utc).isoformat(timespec="seconds")
            if rx_time
            else None
        ),
        "text": text,
        "from_id": from_id,
        "from_num": packet.get("from"),
        "from_long": user.get("longName"),
        "from_short": user.get("shortName"),
        "to_id": to_id,
        "to_num": to_num,
        "direct": to_num is not None and to_num != BROADCAST_NUM and to_id not in BROADCAST_IDS,
        "channel": packet.get("channel", 0),
        "channel_name": _channel_name(interface, packet.get("channel", 0)),
        "packet_id": packet.get("id"),
        "rx_snr": packet.get("rxSnr"),
        "rx_rssi": packet.get("rxRssi"),
        "hop_start": packet.get("hopStart"),
        "hop_limit": packet.get("hopLimit"),
        "hops_away": node.get("hopsAway"),
        "portnum": portnum,
        "want_ack": packet.get("wantAck"),
        "pki_encrypted": packet.get("pkiEncrypted"),
        # Kept because a message from the field is much more useful with the
        # sender's last known position attached.
        "sender_lat": position.get("latitude"),
        "sender_lon": position.get("longitude"),
    }
    return record


def _channel_name(interface, index: int) -> str | None:
    try:
        channels = getattr(interface, "localNode", None).channels
    except AttributeError:
        return None
    if not channels or index is None or index >= len(channels):
        return None
    name = getattr(channels[index].settings, "name", "")
    return name or ("primary" if index == 0 else None)


# --- the listener ------------------------------------------------------------


class Listener:
    def __init__(self, settings: Settings, notifier: Notifier):
        self.s = settings
        self.notifier = notifier
        self.my_num: int | None = None
        self.my_id: str | None = None
        self._seen: deque[int] = deque(maxlen=SEEN_CAPACITY)
        self._seen_set: set[int] = set()
        self._stop = threading.Event()
        self._lost = threading.Event()

    def accepts(self, record: dict) -> tuple[bool, str]:
        """Decide whether this message is 'intended for us'."""
        if record["direct"]:
            if self.my_num is not None and record.get("to_num") != self.my_num:
                return False, "direct message addressed to another node"
            return True, "direct"
        if self.s.dm_only:
            return False, "broadcast, and dm_only is set"
        if self.s.channel_allowlist:
            name = record.get("channel_name") or str(record.get("channel"))
            if name not in self.s.channel_allowlist:
                return False, f"channel {name!r} not in allowlist"
        return True, "broadcast on a watched channel"

    def record_seen(self, packet_id) -> bool:
        """True the first time a packet id is seen, False for a repeat."""
        if packet_id is None:
            return True
        if packet_id in self._seen_set:
            return False
        if len(self._seen) == self._seen.maxlen:
            self._seen_set.discard(self._seen[0])
        self._seen.append(packet_id)
        self._seen_set.add(packet_id)
        return True

    def append_ledger(self, record: dict) -> None:
        path = self.s.ledger
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    def on_receive(self, packet=None, interface=None, **_kwargs) -> None:
        # Never let an exception in here kill the pubsub thread; a listener
        # that stops recording without saying so is the worst outcome.
        try:
            self._on_receive(packet, interface)
        except Exception:  # noqa: BLE001 - deliberate catch-all at the boundary
            LOG.exception("failed to handle a packet")

    def _on_receive(self, packet, interface) -> None:
        if not isinstance(packet, dict):
            return
        record = build_record(packet, interface)
        if record is None:
            return
        if not self.record_seen(record.get("packet_id")):
            LOG.debug("duplicate packet %s ignored", record.get("packet_id"))
            return

        accepted, why = self.accepts(record)
        record["accepted"] = accepted
        record["decision"] = why

        if not accepted:
            self.append_ledger(record)
            LOG.info("recorded but not forwarded (%s)", why)
            return

        LOG.info(
            "message from %s on channel %s: %d chars",
            record.get("from_id"),
            record.get("channel_name") or record.get("channel"),
            len(record["text"]),
        )
        # The ledger row is written after the notifications so it can record
        # whether they succeeded, and in a finally so a failing notifier still
        # leaves evidence that the message arrived.
        try:
            record["email_sent"] = self.notifier.email(record)
            record["sms_sent"] = self.notifier.sms(record)
        finally:
            self.append_ledger(record)

    def on_connection_lost(self, *_args, **_kwargs) -> None:
        LOG.warning("connection to the radio was lost")
        self._lost.set()

    def stop(self, *_args) -> None:
        LOG.info("stopping")
        self._stop.set()
        self._lost.set()

    def run(self) -> int:
        import meshtastic.serial_interface  # imported late: costly and optional
        from pubsub import pub

        pub.subscribe(self.on_receive, "meshtastic.receive")
        pub.subscribe(self.on_connection_lost, "meshtastic.connection.lost")

        while not self._stop.is_set():
            self._lost.clear()
            iface = None
            try:
                LOG.info("opening %s", self.s.port)
                iface = meshtastic.serial_interface.SerialInterface(devPath=self.s.port)
                info = getattr(iface, "myInfo", None)
                self.my_num = getattr(info, "my_node_num", None)
                self.my_id = f"!{self.my_num:08x}" if self.my_num else None
                if not self.s.device_id:
                    node = (iface.nodes or {}).get(self.my_id) or {}
                    short = (node.get("user") or {}).get("shortName")
                    if short:
                        self.notifier.device_id = short
                        LOG.info("device id taken from the radio: %s", short)
                    else:
                        LOG.warning(
                            "no device id in the config and the radio did not "
                            "report a short name; phone-book routing is inactive"
                        )
                LOG.info(
                    "listening as %s (%s), dm_only=%s, ledger=%s",
                    self.my_id,
                    self.my_num,
                    self.s.dm_only,
                    self.s.ledger,
                )
                while not self._lost.wait(timeout=1.0):
                    pass
            except KeyboardInterrupt:
                self.stop()
            except Exception as exc:  # noqa: BLE001
                LOG.error("radio connection failed: %s", exc)
            finally:
                if iface is not None:
                    try:
                        iface.close()
                    except Exception:  # noqa: BLE001
                        pass
            if self._stop.is_set():
                break
            LOG.info("reconnecting in %ds", self.s.reconnect_secs)
            if self._stop.wait(timeout=self.s.reconnect_secs):
                break
        return 0


# --- entry point -------------------------------------------------------------


def self_test(settings: Settings, notifier: Notifier) -> int:
    """Prove the notification paths without waiting for a radio message."""
    record = {
        "received_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "text": "Listener self-test. If you have this, the path works.",
        "from_id": "!f6fb8e00",
        "from_long": "listener self-test",
        "from_short": "TEST",
        "to_id": "!f6fb8e00",
        "channel": 2,
        "channel_name": "ftg-priv",
        "direct": True,
        "packet_id": 0,
        "rx_snr": 0.0,
        "rx_rssi": 0,
        "portnum": "TEXT_MESSAGE_APP",
    }
    recipients = settings.sms_recipients(notifier.device_id)
    print(f"device id: {notifier.device_id or '(none -- phone book cannot match)'}")
    for address, person in recipients:
        local, _, domain = address.partition("@")
        print(f"  sms -> {person or '(literal)'}: {local[:3]}***@{domain}")
    email_ok = notifier.email(record)
    sms_ok = notifier.sms(record)
    print(f"email: {'sent' if email_ok else 'NOT sent'}")
    print(f"sms:   {'sent' if sms_ok else 'NOT sent'}")
    print(
        "\nHanded to the local MTA only. Acceptance by the relay is not delivery --\n"
        "check the inbox and the handset, and check the mail log for the result."
    )
    return 0 if (email_ok or not settings.email_enabled) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-c", "--config", required=True, help="path to listener.conf")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="send one test notification through email and SMS, then exit",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="log what would be sent, send nothing"
    )
    parser.add_argument(
        "--device-id",
        help="which radio this listener speaks for, overriding [listen] device_id. "
        "Mainly for --self-test, which has no radio to read a short name from.",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
    )
    # The Meshtastic library logs every packet at INFO, which buries ours.
    logging.getLogger("meshtastic").setLevel(logging.WARNING)

    try:
        settings = Settings(Path(args.config))
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    notifier = Notifier(settings, dry_run=args.dry_run)
    if args.device_id:
        notifier.device_id = args.device_id
    if args.self_test:
        return self_test(settings, notifier)

    listener = Listener(settings, notifier)
    signal.signal(signal.SIGINT, listener.stop)
    signal.signal(signal.SIGTERM, listener.stop)
    return listener.run()


if __name__ == "__main__":
    sys.exit(main())
