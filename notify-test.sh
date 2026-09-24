#!/usr/bin/env bash
# ===============================================================
# Script:   notify-test.sh
# Version:  1.0.0
# Date:     2026-09-24
# Purpose:  Send one test message to each configured notification
#           channel (ntfy and/or email via msmtp) and report whether
#           each one was accepted. Uses the same settings as every
#           script that follows the homelab-notifications convention:
#           NTFY_URL, NTFY_TOKEN, EMAIL_TO, MSMTP_ACCOUNT.
# Usage:    notify-test.sh [CONFIG_FILE]
#           With a config file, settings are read from it (bash syntax).
#           Without one, they're read from the environment.
#           Run it as the same user your scripts run as (usually root),
#           since msmtp reads that user's config.
# License:  MIT
# ===============================================================
set -uo pipefail

if [ $# -gt 1 ] || [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
    sed -n '11,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi

if [ $# -eq 1 ]; then
    if [ ! -r "$1" ]; then
        echo "Cannot read config file: $1" >&2
        exit 2
    fi
    # shellcheck disable=SC1090
    source "$1"
fi

NTFY_URL="${NTFY_URL:-}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
EMAIL_TO="${EMAIL_TO:-}"
MSMTP_ACCOUNT="${MSMTP_ACCOUNT:-default}"

host="$(hostname)"
now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
failed=0
tested=0

# --- ntfy ---
if [ -n "$NTFY_URL" ]; then
    tested=$((tested + 1))
    auth=()
    [ -n "$NTFY_TOKEN" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
        -H "Title: Notification test from $host" \
        -H "Priority: 3" \
        -H "Tags: test_tube" \
        "${auth[@]}" \
        -d "If you can read this, ntfy notifications from $host work. ($now)" \
        "$NTFY_URL")
    case "$code" in
        200) echo "ntfy:  OK   (HTTP 200) -> $NTFY_URL" ;;
        401|403) echo "ntfy:  FAIL (HTTP $code) -> token missing, wrong, or lacks write access to this topic"; failed=1 ;;
        000) echo "ntfy:  FAIL (no response) -> server unreachable; check NTFY_URL and the network"; failed=1 ;;
        *) echo "ntfy:  FAIL (HTTP $code) -> $NTFY_URL"; failed=1 ;;
    esac
else
    echo "ntfy:  skipped (NTFY_URL is empty)"
fi

# --- email ---
if [ -n "$EMAIL_TO" ]; then
    tested=$((tested + 1))
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "email: FAIL -> msmtp is not installed"
        failed=1
    elif err=$(printf 'To: %s\nSubject: Notification test from %s\n\nIf you can read this, email notifications from %s work. (%s)\n' \
            "$EMAIL_TO" "$host" "$host" "$now" | msmtp -a "$MSMTP_ACCOUNT" "$EMAIL_TO" 2>&1); then
        echo "email: OK   (accepted by SMTP server, account '$MSMTP_ACCOUNT') -> $EMAIL_TO"
        echo "       Delivery can take a few minutes; check spam if it doesn't arrive."
    else
        echo "email: FAIL (account '$MSMTP_ACCOUNT') -> $EMAIL_TO"
        printf '%s\n' "$err" | sed 's/^/       /'
        failed=1
    fi
else
    echo "email: skipped (EMAIL_TO is empty)"
fi

if [ "$tested" -eq 0 ]; then
    echo "Nothing to test: set NTFY_URL and/or EMAIL_TO."
    exit 2
fi
exit "$failed"
