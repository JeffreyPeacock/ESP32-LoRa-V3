# Mail relay setup for the FTG1 Raspberry Pi

**Scope: outbound email only.** Everything else about this machine — the LoRa
radio, the listener daemon — is someone else's problem and is not needed to do
this work or to verify it.

## What you are being asked to build

A Raspberry Pi 4 running **Debian 13 (Trixie)**, arm64, needs to send a small
number of automated emails per day through `mail.wonkware.com`. It receives no
mail and must not accept any from the network.

Concretely, an application on the box calls:

```
/usr/sbin/sendmail -t -oi -f ftg1@ftg
```

and expects the message to leave the machine. That is the entire integration
surface. If `sendmail` works, the application works.

Two kinds of destination, both ordinary SMTP:

| Destination | Example | Note |
|---|---|---|
| A normal mailbox | `someone@proton.me` | |
| A carrier SMS gateway | `<10 digits>@msg.fi.google.com` | Google Fi turns the email into a text message |

The second is why deliverability matters more than volume: a carrier gateway
**discards mail it does not like without reporting anything**, so a
misconfiguration looks identical to a working system until someone notices a
text never arrived.

Expected volume is a few messages a day, each under 1 KB.

## What you need from the relay administrator

**The SASL username and password for `mail.wonkware.com`.** They are not in any
repository and must not be copied out of another host's
`/etc/postfix/sasl_passwd`, which is `0600` root-only for that reason.

Also worth confirming with them, while you have their attention: that the
account is permitted to send as **`ftg1@flagstafftechgroup.org`**. See
"Sender rewriting" below.

## Install

Choose **"Satellite system"** at the debconf prompt — deliver nothing locally,
relay everything to a smarthost. System mail name can be left at the hostname.

```bash
sudo apt install postfix
```

## Configure

These are the settings taken from a host where this already works:

```bash
sudo postconf -e \
  'relayhost = [mail.wonkware.com]:587' \
  'smtp_sasl_auth_enable = yes' \
  'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd' \
  'smtp_sasl_security_options = noanonymous' \
  'smtp_tls_security_level = encrypt' \
  'smtp_tls_CApath = /etc/ssl/certs' \
  'smtp_generic_maps = hash:/etc/postfix/generic' \
  'smtp_address_preference = ipv4' \
  'inet_interfaces = loopback-only'
```

Two of those are load-bearing in ways that are easy to miss:

- **`inet_interfaces = loopback-only`** — the Pi must not listen for mail on
  the network. It only ever sends its own.
- **`smtp_tls_security_level = encrypt`** — not `may`. The credentials go over
  this connection; do not let it fall back to plaintext.

### Credentials

```bash
sudo install -m 600 /dev/null /etc/postfix/sasl_passwd
sudo tee /etc/postfix/sasl_passwd >/dev/null <<'EOF'
[mail.wonkware.com]:587    USER:PASSWORD
EOF
sudo postmap /etc/postfix/sasl_passwd
```

The brackets matter — they tell postfix not to do an MX lookup on that name.
The `.db` postmap generates inherits the `0600` mode; check that it did.

### Sender rewriting

The application sends as `ftg1@ftg`, which is a local-only token, not a real
address. Map it to the real one:

```bash
sudo tee -a /etc/postfix/generic >/dev/null <<'EOF'
ftg1@ftg    ftg1@flagstafftechgroup.org
EOF
sudo postmap /etc/postfix/generic
sudo systemctl reload postfix
```

**Do not substitute a different sender domain without checking SPF.** This
particular one is correct because the DNS already authorises the relay:

```bash
dig +short TXT flagstafftechgroup.org | grep spf1
#   v=spf1 include:wonkware.com -all
dig +short TXT wonkware.com | grep spf1
#   v=spf1 ip4:104.237.154.196 ... -all
dig +short A mail.wonkware.com
#   104.237.154.196
```

The include chain reaches the relay's own IP, so SPF passes. Both domains
publish `p=quarantine` DMARC, and because `smtp_generic_maps` rewrites the
envelope sender and the `From:` header to the same address, DMARC aligns too.

A sender on a domain that does *not* authorise this relay fails SPF and is
treated **worse** than an unbranded address would be. That is the whole reason
this map entry exists.

## Verify

The application is not needed for this. Send one message by hand:

```bash
printf 'Subject: pi mail test\nTo: you@example.com\n\nbody\n' \
  | sendmail -f ftg1@ftg -t

sudo journalctl -u postfix -n 20 --no-pager | grep -E 'from=<|status='
```

You are looking for two things:

```
from=<ftg1@ftg>
status=sent (250 2.0.0 Ok: queued as ...)
```

Anything else is the actual problem, and the log names it:

| Log says | Means |
|---|---|
| `SASL authentication failed` | wrong credentials, or the account cannot send as that sender |
| `Connection refused` / `timed out` | egress on 587 is blocked, or the relay is unreachable |
| `status=bounced` | the relay accepted the connection and rejected the message; the text says why |
| `status=deferred` | transient; it will retry, check `mailq` |
| nothing at all | postfix is not running, or the message never reached it |

**Then confirm the sender was actually rewritten**, which the local log does not
show — the rewrite happens on the outbound leg. Check the `From:` on the
received message: it must read `ftg1@flagstafftechgroup.org`, not
`ftg1@ftg` and not `<something>@<hostname>`.

## One open problem you may be able to solve

Messages sent this way currently arrive with **`[Potential Spam]` prepended to
the subject.** Two causes have already been found and fixed on the sending
side:

- the envelope sender and the `From:` header disagreed, because the sending
  application was not passing `-f`. It does now.
- the messages carried no `Subject:` header at all. They do now.

The tag survived both, so whatever is adding it is on the relay or at the
receiving carrier. If `mail.wonkware.com` runs a content filter, an allowlist
entry for `ftg1@flagstafftechgroup.org` is likely the real fix — automated
notifications from a new sender are close to unfixable by message content
alone.

The evidence is in the `X-Spam-Status` and `X-Spam-Report` headers of a
delivered message; those name the scanner and the exact rules that fired, with
scores. Worth checking whether the tag appears on mail to an ordinary mailbox
or only on mail to the SMS gateway — if only the latter, it is Google's filter
and not yours.

## Summary of what must be true when you are done

- `sendmail -f ftg1@ftg -t` exits 0 and the log shows `status=sent`
- the delivered message's `From:` reads `ftg1@flagstafftechgroup.org`
- `/etc/postfix/sasl_passwd` and its `.db` are `0600`, root-owned
- postfix listens on loopback only: `ss -lnt | grep ':25 '` shows
  `127.0.0.1:25` and `[::1]:25`, and no other address
- `mailq` is empty
