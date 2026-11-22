#!/usr/bin/env bash
# Installs and launches a built app (.ipa) on the connected iPhone, or the one with the given UDID,
# for `just phone-install` and `just phone-install-release`. The app and its bundle identifier come
# from the .ipa itself.
#
# A locked iPhone is waited for: it says so once, tries again every PHONE_UNLOCK_POLL seconds (5),
# and gives up after PHONE_UNLOCK_WAIT seconds (1800). Starting another install of the same app on
# the same iPhone ends a wait already running, so the newest build is the one left launched.
# devicectl output counts as locked when it says "locked" in any case ("Locked", "was still locked")
# or names CoreDeviceError 10003. Anything else, CoreDeviceError 12018 (the developer disk image's
# metadata unreadable) included, is a failure tried three times running before giving up, since
# waiting half an hour on a real fault would hide it.
#
# usage: install-iphone-app.sh <ipa> [udid]
set -euo pipefail

ipa=$1
udid=${2:-}
[[ -n "$udid" ]] || udid=$(bash "$(dirname "$0")/connected-iphone.sh")
poll=${PHONE_UNLOCK_POLL:-5}
limit=${PHONE_UNLOCK_WAIT:-1800}

app=$(mktemp -d)
waiter=""
cleanup() {
    rm -rf "$app"
    [[ -n "$waiter" && "$(cat "$waiter" 2>/dev/null)" == "$$" ]] && rm -f "$waiter"
    return 0
}
trap cleanup EXIT
trap 'echo "A newer install replaced this one; it installs the newest build." >&2; exit 3' TERM
# Copied out first, so a build that lands while this waits doesn't change what this installs.
unzip -q "$ipa" -d "$app"
bundle=$(find "$app/Payload" -maxdepth 1 -name '*.app' | head -1)
[[ -n "$bundle" ]] || { echo "$ipa holds no Payload/*.app." >&2; exit 1; }
identifier=$(plutil -extract CFBundleIdentifier raw "$bundle/Info.plist")

# The install waiting for this iPhone, by process id; only a wait writes it, never an install
# under way. Named for the app too, so installing two projects on one phone ends neither's wait.
waiter="${TMPDIR:-/tmp}/phone-install-$identifier-$udid.pid"
if [[ -f "$waiter" ]]; then
    earlier=$(cat "$waiter")
    if [[ "$earlier" != "$$" ]] && kill -0 "$earlier" 2>/dev/null; then
        kill -TERM "$earlier" 2>/dev/null || true
    fi
    rm -f "$waiter"
fi

# The limit as a person would say it.
if ((limit >= 120)); then span="$((limit / 60)) minutes"; else span="$limit seconds"; fi

# Runs a devicectl step until it succeeds. While the iPhone is locked (see the header) it says so
# once and tries again every $poll seconds, up to the limit; any other failure is tried again twice,
# since a phone on Wi-Fi drops its tunnel now and then, before giving up. The step itself is the
# probe: lockState's passcodeRequired is undocumented and may not mean "locked now".
waited=0
said=false
attempt() {
    local out failures=0
    out=$(mktemp)
    while true; do
        if perl -e 'alarm 120; exec @ARGV' xcrun devicectl "$@" >"$out" 2>&1; then
            rm -f "$out"
            [[ "$said" == true ]] && rm -f "$waiter"
            return 0
        fi
        if grep -qiE "locked|CoreDeviceError error 10003" "$out"; then
            failures=0
            if [[ "$said" == false ]]; then
                echo "The iPhone is locked; waiting up to $span for it to be unlocked..." >&2
                echo "$$" >"$waiter"
                said=true
            fi
            if ((waited >= limit)); then
                rm -f "$out"
                echo "The iPhone stayed locked for $span; the app was not launched. Unlock it and run the install again." >&2
                exit 2
            fi
            waited=$((waited + poll))
        else
            failures=$((failures + 1))
            if ((failures >= 3)); then
                tail -5 "$out" >&2
                rm -f "$out"
                echo "The iPhone ($udid) can't be reached: is it still connected?" >&2
                exit 1
            fi
        fi
        # In the background and waited for, so the TERM a newer install sends ends the wait at once.
        sleep "$poll" &
        wait $!
    done
}

attempt device install app --device "$udid" "$bundle"
echo "Installed on the iPhone." >&2
attempt device process launch --device "$udid" "$identifier"
echo "Launched." >&2
