#!/usr/bin/env bash
# Prints the UDID of the first iPhone connected to this Mac (by cable, or over the network once
# paired), for `just phone-install` and `just phone-provision`. Prints nothing, and fails, when none is.
#
# devicectl lists the simulators too, so they are left out by their `reality`. A phone this Xcode
# doesn't know yet (a model newer than it) has no `reality` key at all, so the filter excludes
# "simulated" rather than requiring "physical".
set -euo pipefail

list=$(mktemp)
trap 'rm -f "$list"' EXIT
xcrun devicectl list devices --json-output "$list" >/dev/null
udid=$(python3 -I -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
print(next((d["hardwareProperties"]["udid"] for d in devices
            if d["hardwareProperties"].get("deviceType") == "iPhone"
            and d["hardwareProperties"].get("reality") != "simulated"
            and d.get("connectionProperties", {}).get("tunnelState") != "unavailable"), ""))
' "$list")
[[ -n "$udid" ]] || { echo "No iPhone connected. Plug it in, unlock it, and trust this Mac." >&2; exit 1; }
echo "$udid"
