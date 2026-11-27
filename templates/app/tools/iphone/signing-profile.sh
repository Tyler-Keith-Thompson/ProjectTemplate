#!/usr/bin/env bash
# Prints which development profile signs the app for this iPhone, as Apps/ProjectName/BUILD.bazel's
# signing_profile define takes it: `app` for "iOS Team Provisioning Profile: <bundle identifier>",
# `wildcard` for "iOS Team Provisioning Profile: *". Xcode's automatic signing makes the first, but
# signs with the second instead when the team already has it and the app needs no capability, so
# either can be the one that holds the iPhone. The bundle identifier's comes first when both do.
# Fails, saying so, when neither includes the iPhone.
#
# usage: signing-profile.sh <bundle identifier> [udid]
set -euo pipefail

identifier=$1
udid=${2:-}
[[ -n "$udid" ]] || udid=$(bash "$(dirname "$0")/connected-iphone.sh")

found=
for profile in "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
    "$HOME"/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision; do
    [[ -f "$profile" ]] || continue
    plist=$(security cms -D -i "$profile" 2>/dev/null) || continue
    case $(plutil -extract Name raw - <<<"$plist" 2>/dev/null) in
        "iOS Team Provisioning Profile: $identifier") kind=app ;;
        "iOS Team Provisioning Profile: *") kind=wildcard ;;
        *) continue ;;
    esac
    plutil -extract ProvisionedDevices json -o - - <<<"$plist" 2>/dev/null | grep -q "\"$udid\"" || continue
    [[ "$kind" == app ]] && { echo app; exit 0; }
    found=wildcard
done

[[ -n "$found" ]] && { echo "$found"; exit 0; }
echo "No provisioning profile includes this iPhone ($udid). Run just phone-provision first." >&2
exit 1
