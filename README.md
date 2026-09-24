# homelab-notifications

How the scripts in my homelab repos send alerts, and how to set that up on your own machine. Every repo that links here uses the same four settings, so you configure notifications once and reuse them everywhere.

Two channels are supported, and you can use either or both:

- **[ntfy](https://ntfy.sh)**: push notifications to your phone or desktop, with priorities, so an urgent failure buzzes and a routine progress update doesn't.
- **Email** via [msmtp](https://marlam.de/msmtp/), a lightweight "send-only" mail client. Good for a permanent record, and for alerts that carry full log output.

## The four settings

Every script reads these, usually from its own config file (for example `/etc/snapraid-toolkit.conf`):

| Setting | Example | Meaning |
|---|---|---|
| `NTFY_URL` | `https://ntfy.sh/my-random-topic-8f3k2` | Full URL of the ntfy topic to publish to. Empty = no ntfy. |
| `NTFY_TOKEN` | `tk_...` | Access token, only needed if the topic requires login. Empty = no auth. |
| `EMAIL_TO` | `you@example.com` | Where email alerts go. Empty = no email. |
| `MSMTP_ACCOUNT` | `default` | Which account from your msmtp config to send with. |

An empty setting turns that channel off. Nothing else needs changing.

## Test your setup

[`notify-test.sh`](notify-test.sh) sends one test message on each channel you've configured and tells you exactly what worked:

```bash
sudo ./notify-test.sh /etc/snapraid-toolkit.conf      # read settings from a tool's config file
NTFY_URL=https://ntfy.sh/my-topic ./notify-test.sh    # or from environment variables
```

```
ntfy:  OK   (HTTP 200) -> https://ntfy.sh/my-random-topic-8f3k2
email: OK   (accepted by SMTP server, account 'default') -> you@example.com
       Delivery can take a few minutes; check spam if it doesn't arrive.
```

**Run it as the same user your scripts run as**, usually root (`sudo`). msmtp reads that user's own config file, so a test as yourself proves nothing about what root can send.

Exit code: `0` if everything configured worked, `1` if anything failed, `2` if nothing was configured.

---

## Setting up ntfy

### Option A: the public ntfy.sh server (easiest)

1. Install the ntfy app ([Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy), [iOS](https://apps.apple.com/us/app/ntfy/id1625396347)) or open [ntfy.sh/app](https://ntfy.sh/app) in a browser.
2. Subscribe to a topic with a **long, random name**, for example `homelab-alerts-8f3k2q9x`.
3. Set `NTFY_URL="https://ntfy.sh/homelab-alerts-8f3k2q9x"` and leave `NTFY_TOKEN` empty.

> **On the public server, the topic name is the password.** Anyone who knows or guesses it can read your alerts and send you fake ones. Use a random name, and don't paste it anywhere public. Alerts may include hostnames, container names and log excerpts; if that matters to you, self-host.

### Option B: self-hosted ntfy (more private)

Run your own ntfy server ([install docs](https://docs.ntfy.sh/install/)), then lock down publishing so only your scripts can send:

```bash
# in the ntfy server's server.yml
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "read-only"     # anyone can subscribe; publishing needs a login

# create a user just for your scripts, allowed to publish to every topic, and give it a token
ntfy user add ntfy-bot
ntfy access ntfy-bot '*' write-only
ntfy token add ntfy-bot              # prints tk_...
```

Then set `NTFY_URL="https://ntfy.example.com/snapraid"` and `NTFY_TOKEN="tk_..."`. Use `deny-all` instead of `read-only` if subscribers should log in too.

**Where to run it:** somewhere that doesn't depend on the things it reports on. If ntfy runs as a container on the same Docker host whose failures it's meant to report, an outage of that host also silences the alert. A small separate VM or LXC is a good home for it.

### Priorities used by these scripts

| Priority | Name | Used for |
|---|---|---|
| 5 | urgent | Failures that need action: a sync failed, a container didn't come back |
| 4 | high | Probable problems: a long job seems stalled |
| 3 | default | Warnings and notices: disk nearly full, a stall recovered |
| 2 | low | Progress updates and routine completions |

In the ntfy app you can set per-topic notification sounds, or mute low priorities entirely.

---

## Setting up email (msmtp)

msmtp hands mail to a real SMTP server (Gmail, Fastmail, your ISP, your own mail server). It doesn't receive mail and doesn't run as a daemon.

### 1. Install

```bash
sudo apt install msmtp            # Debian / Ubuntu / Proxmox
sudo pacman -S msmtp              # Arch
sudo dnf install msmtp            # Fedora
```

### 2. Create the config for the user your scripts run as

Most scripts in these repos run as **root** (from systemd), so root needs the config: `/root/.msmtprc`. Scripts that run as a normal user need it in that user's `~/.msmtprc` instead.

```bash
sudo vi /root/.msmtprc
sudo chmod 600 /root/.msmtprc     # msmtp refuses a config readable by others if it holds a password
```

Example using Gmail:

```
# /root/.msmtprc
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           your.sender@gmail.com
user           your.sender@gmail.com
password       your-16-char-app-password

# Optional: a separate account per tool, so alerts show a clear sender name.
# Scripts pick it with MSMTP_ACCOUNT="snapraid".
account        snapraid : default
from_full_name SnapRAID
```

Things that commonly go wrong:

- **Gmail needs an [app password](https://myaccount.google.com/apppasswords)**, not your normal password. It requires 2-step verification to be on.
- **`from` must be a bare address.** Put a display name in `from_full_name`, never `from "Name <addr>"`; Gmail rejects the latter.
- **Use an absolute path** for `tls_trust_file`, and for any file referenced by `passwordeval`. Some callers, such as systemd units, run with a minimal environment where `~` doesn't expand the way it does in your shell.
- **`tls_trust_file` differs by distribution:** `/etc/ssl/certs/ca-certificates.crt` on Debian/Ubuntu/Arch, `/etc/pki/tls/certs/ca-bundle.crt` on Fedora/RHEL.

### 3. Keep the password out of the file (optional, recommended)

Instead of a plain `password` line, msmtp can run a command to fetch it:

```
passwordeval "gpg --quiet --decrypt /root/.msmtp-password.gpg"
```

For unattended scripts, the GPG key must be usable without a prompt. That means either a key without a passphrase that lives only in root's keyring, or a running agent. A root-only `chmod 600` file with a plain password is a reasonable tradeoff on a single-user server; just don't commit it anywhere.

### 4. Test

```bash
sudo ./notify-test.sh /etc/snapraid-toolkit.conf
```

or directly:

```bash
printf 'Subject: test\n\nhello\n' | sudo msmtp -a default you@example.com
```

If it fails, `/var/log/msmtp.log` (from the `logfile` line above) and `msmtp --debug` show the SMTP conversation.

---

## For script authors

The convention, so new scripts behave like the existing ones:

```bash
NTFY_URL=""; NTFY_TOKEN=""; EMAIL_TO=""; MSMTP_ACCOUNT="default"
[ -f "$CONF" ] && source "$CONF"

notify() {   # notify "Title" "Body" [priority] [tags]
    local title="$1" body="$2" priority="${3:-3}" tags="${4:-}"
    if [ -n "$NTFY_URL" ]; then
        local auth=()
        [ -n "$NTFY_TOKEN" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
        curl -s -o /dev/null -H "Title: $title" -H "Priority: $priority" \
            -H "Tags: $tags" "${auth[@]}" -d "$body" "$NTFY_URL"
    fi
    if [ -n "$EMAIL_TO" ]; then
        printf 'Subject: %s\n\n%s\n' "$title" "$body" | msmtp -a "$MSMTP_ACCOUNT" "$EMAIL_TO"
    fi
}
```

- Never hardcode a token, address or server in a script. Read everything from the config file.
- Make every channel optional: an empty setting skips it without error.
- Put full log output in the email; keep the ntfy message short enough to read on a lock screen.

## Repos that use this

- [snapraid-mergerfs-toolkit](https://github.com/pinoybear/snapraid-mergerfs-toolkit): SnapRAID + mergerfs automation

## License

MIT
