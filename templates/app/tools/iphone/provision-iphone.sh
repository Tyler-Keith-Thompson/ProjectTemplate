#!/usr/bin/env bash
# Has Xcode's automatic signing register the iPhone and make the app's development provisioning
# profile, then checks that the profile includes the iPhone, for `just phone-provision`: once per
# Mac, and again for each new iPhone. Bazel's device builds sign with that profile
# (Apps/ProjectName/BUILD.bazel).
#
# The team is DEVELOPMENT_TEAM when it is set, else the team of the first Apple Development
# certificate in the Keychain (the one Xcode makes once you sign in under Settings > Accounts).
# Nothing in the repository names it.
#
# usage: provision-iphone.sh <xcodeproj> <scheme> <bundle identifier> [udid]
set -euo pipefail

project=$1
scheme=$2
identifier=$3
udid=${4:-}
[[ -n "$udid" ]] || udid=$(bash "$(dirname "$0")/connected-iphone.sh")

developer_mode_off() {
    echo "Developer Mode is off on this iPhone ($udid). Turn it on in Settings > Privacy & Security > Developer Mode, let the iPhone restart, then run just phone-provision again." >&2
    exit 1
}

# Developer Mode first: with it off, xcodebuild fails in a way that says little.
list=$(mktemp)
log=$(mktemp)
trap 'rm -f "$list" "$log"' EXIT
xcrun devicectl list devices --json-output "$list" >/dev/null
mode=$(python3 -I -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
print(next((d.get("deviceProperties", {}).get("developerModeStatus", "") for d in devices
            if d["hardwareProperties"].get("udid") == sys.argv[2]), ""))
' "$list" "$udid")
[[ "$mode" == disabled ]] && developer_mode_off

team=${DEVELOPMENT_TEAM:-}
if [[ -z "$team" ]]; then
    team=$(security find-certificate -c "Apple Development" -p 2>/dev/null |
        openssl x509 -noout -subject -nameopt multiline 2>/dev/null |
        sed -n 's/^ *organizationalUnitName *= *//p' | head -1) || true
fi
[[ -n "$team" ]] || {
    echo "No development team: sign in to your Apple account in Xcode (Settings > Accounts), or set DEVELOPMENT_TEAM to your team ID." >&2
    exit 1
}

# The generated project leaves signing to Bazel, so signing is allowed just for this; the build
# needn't succeed, only the profile Xcode makes on the way.
xcodebuild -project "$project" -scheme "$scheme" -destination "id=$udid" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$team" build >"$log" 2>&1 || true

for profile in "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
    "$HOME"/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
    [[ -f "$profile" ]] || continue
    plist=$(security cms -D -i "$profile" 2>/dev/null) || continue
    [[ $(plutil -extract Name raw - <<<"$plist" 2>/dev/null) == "iOS Team Provisioning Profile: $identifier" ]] || continue
    if plutil -extract ProvisionedDevices json -o - - <<<"$plist" 2>/dev/null | grep -q "\"$udid\""; then
        echo "The provisioning profile includes this iPhone ($udid). Next: just phone-install"
        exit 0
    fi
done

grep -qi "developer mode" "$log" && developer_mode_off
echo "xcodebuild said:" >&2
{ grep -E "error:" "$log" || tail -10 "$log"; } | head -10 >&2
echo "No provisioning profile includes this iPhone ($udid) yet. Open $project, pick the $scheme scheme and your iPhone, and check Signing & Capabilities for what Xcode needs." >&2
exit 1
