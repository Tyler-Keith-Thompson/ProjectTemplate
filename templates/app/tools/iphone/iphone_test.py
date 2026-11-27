"""Tests of the iPhone scripts (`just phone-install`, `just phone-provision`) against stand-ins.

A stand-in `xcrun` on PATH answers `devicectl list devices` with a device list the test writes, and
every other devicectl call with the next line of a plan: `ok` succeeds, anything else is printed as
devicectl's failure. Stand-in `xcodebuild` and `security` do the same for provisioning. No iPhone,
Xcode or real devicectl is involved.
"""

import json
import os
import pathlib
import plistlib
import stat
import subprocess
import tempfile
import time
import unittest
import zipfile

HERE = pathlib.Path("tools/iphone").resolve()
INSTALL = HERE / "install-iphone-app.sh"
CONNECTED = HERE / "connected-iphone.sh"
PROVISION = HERE / "provision-iphone.sh"
SIGNING_PROFILE = HERE / "signing-profile.sh"

STILL_LOCKED = "ERROR: The operation failed because the device was still locked. (com.apple.dt.CoreDeviceError error 10003 (0x2713))"
DISK_IMAGE = "ERROR: Failed to read the metadata for the developer disk image mounted on this device. (com.apple.dt.CoreDeviceError error 12018 (0x2EF2))"

STAND_IN_XCRUN = """#!/usr/bin/env bash
echo "$*" >>"{work}/calls"
if [[ "$1 $2 $3" == "devicectl list devices" ]]; then
    cp "{work}/devices.json" "$5"
    exit 0
fi
line=$(head -1 "{work}/plan")
tail -n +2 "{work}/plan" >"{work}/plan.rest" && mv "{work}/plan.rest" "{work}/plan"
[[ "$line" == ok ]] && exit 0
echo "$line"
exit 1
"""

# xcodebuild prints what the test gives it, and copies the profile the test gives it where Xcode
# keeps them, as automatic signing would.
STAND_IN_XCODEBUILD = """#!/usr/bin/env bash
echo "$*" >>"{work}/xcodebuild-calls"
cat "{work}/xcodebuild-output" 2>/dev/null
for made in "{work}"/*.mobileprovision; do
    [[ -f "$made" ]] || continue
    mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    cp "$made" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"
done
exit 65
"""

# The profiles the tests write are plain plists, so decoding one is reading it. The Keychain holds
# no certificate.
STAND_IN_SECURITY = """#!/usr/bin/env bash
if [[ "$1" == cms ]]; then cat "$4"; exit 0; fi
exit 44
"""


def device(udid, reality="physical", device_type="iPhone", tunnel="connected", developer_mode="enabled"):
    hardware = {"udid": udid, "deviceType": device_type}
    if reality is not None:
        hardware["reality"] = reality
    return {
        "hardwareProperties": hardware,
        "connectionProperties": {"tunnelState": tunnel},
        "deviceProperties": {"developerModeStatus": developer_mode} if developer_mode else {},
    }


class StandIns:
    """A directory of stand-in tools, a plan for devicectl and a device list."""

    def __init__(self, test, plan=(), devices=(), tmp=None):
        self.work = pathlib.Path(tempfile.mkdtemp())
        test.addCleanup(subprocess.run, ["rm", "-rf", str(self.work)])
        self.tmp = tmp or self.work / "tmp"
        self.tmp.mkdir(exist_ok=True)
        self.home = self.work / "home"
        self.home.mkdir()
        bin_dir = self.work / "bin"
        bin_dir.mkdir()
        for name, body in [("xcrun", STAND_IN_XCRUN), ("xcodebuild", STAND_IN_XCODEBUILD), ("security", STAND_IN_SECURITY)]:
            path = bin_dir / name
            path.write_text(body.format(work=self.work))
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        (self.work / "plan").write_text("".join(line + "\n" for line in plan))
        (self.work / "devices.json").write_text(json.dumps({"result": {"devices": list(devices)}}))
        self.path = f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}"

    def ipa(self, identifier="com.example.app"):
        ipa = self.work / "App.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/App.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": identifier}))
        return ipa

    def environment(self, poll=0, wait=60, **extra):
        return {
            "PATH": self.path,
            "HOME": str(self.home),
            "TMPDIR": str(self.tmp),
            "PHONE_UNLOCK_POLL": str(poll),
            "PHONE_UNLOCK_WAIT": str(wait),
            **extra,
        }

    def calls(self, name="calls"):
        path = self.work / name
        return path.read_text().splitlines() if path.exists() else []


def run(arguments, environment):
    return subprocess.run(["bash", *map(str, arguments)], env=environment, capture_output=True, text=True, timeout=60)


class InstallTests(unittest.TestCase):
    def test_a_phone_still_locked_is_waited_for_until_the_install_succeeds(self):
        stand_ins = StandIns(self, plan=[STILL_LOCKED] * 4 + ["ok", "ok"])

        actual = run([INSTALL, stand_ins.ipa(), "TEST-UDID"], stand_ins.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(len(stand_ins.calls()), 6)
        self.assertEqual(actual.stderr.count("The iPhone is locked; waiting"), 1)
        self.assertIn("Launched.", actual.stderr)

    def test_the_capitalised_locked_is_waited_for(self):
        stand_ins = StandIns(self, plan=["ERROR: Locked (com.apple.dt.CoreDeviceError error 9999)"] * 4 + ["ok", "ok"])

        actual = run([INSTALL, stand_ins.ipa(), "TEST-UDID"], stand_ins.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)

    def test_core_device_error_10003_alone_counts_as_locked(self):
        error = "ERROR: something went wrong (com.apple.dt.CoreDeviceError error 10003 (0x2713))"
        stand_ins = StandIns(self, plan=[error] * 4 + ["ok", "ok"])

        actual = run([INSTALL, stand_ins.ipa(), "TEST-UDID"], stand_ins.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)

    def test_the_install_and_launch_name_the_app_and_bundle_identifier_in_the_ipa(self):
        stand_ins = StandIns(self, plan=["ok", "ok"])

        actual = run([INSTALL, stand_ins.ipa("com.example.greeter"), "TEST-UDID"], stand_ins.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)
        install, launch = stand_ins.calls()
        self.assertTrue(install.startswith("devicectl device install app --device TEST-UDID "), install)
        self.assertTrue(install.endswith("/Payload/App.app"), install)
        self.assertEqual(launch, "devicectl device process launch --device TEST-UDID com.example.greeter")

    def test_another_error_gives_up_after_three_tries(self):
        stand_ins = StandIns(self, plan=[DISK_IMAGE] * 3 + ["ok", "ok"])

        actual = run([INSTALL, stand_ins.ipa(), "TEST-UDID"], stand_ins.environment())

        self.assertEqual(actual.returncode, 1)
        self.assertEqual(len(stand_ins.calls()), 3)
        self.assertIn("can't be reached", actual.stderr)

    def test_a_phone_locked_past_the_wait_gives_up(self):
        stand_ins = StandIns(self, plan=[STILL_LOCKED] * 3)

        actual = run([INSTALL, stand_ins.ipa(), "TEST-UDID"], stand_ins.environment(poll=1, wait=1))

        self.assertEqual(actual.returncode, 2)
        self.assertIn("stayed locked for 1 seconds", actual.stderr)

    def test_no_connected_iphone_fails_before_installing(self):
        stand_ins = StandIns(self, plan=["ok", "ok"], devices=[device("SIM", reality="simulated")])

        actual = run([INSTALL, stand_ins.ipa()], stand_ins.environment())

        self.assertEqual(actual.returncode, 1)
        self.assertIn("No iPhone connected", actual.stderr)
        self.assertEqual(len(stand_ins.calls()), 1)

    def test_a_newer_install_ends_an_earlier_ones_wait(self):
        earlier = StandIns(self, plan=[STILL_LOCKED] * 200)
        newer = StandIns(self, plan=["ok", "ok"], tmp=earlier.tmp)
        waiting = subprocess.Popen(
            ["bash", str(INSTALL), str(earlier.ipa()), "TEST-UDID"],
            env=earlier.environment(poll=1, wait=600),
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(waiting.kill)
        # The gate: the earlier install records itself as waiting once it has said so.
        waiter = earlier.tmp / "phone-install-com.example.app-TEST-UDID.pid"
        deadline = time.monotonic() + 30
        while not waiter.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(waiter.exists(), "the earlier install never started waiting")

        actual = run([INSTALL, newer.ipa(), "TEST-UDID"], newer.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)
        _, earlier_output = waiting.communicate(timeout=30)
        self.assertEqual(waiting.returncode, 3)
        self.assertIn("A newer install replaced this one", earlier_output)
        self.assertFalse(waiter.exists())


class ConnectedIPhoneTests(unittest.TestCase):
    def test_a_phone_without_a_reality_key_is_found(self):
        devices = [device("SIM", reality="simulated"), device("NEW-PHONE", reality=None)]
        stand_ins = StandIns(self, devices=devices)

        actual = run([CONNECTED], stand_ins.environment())

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(actual.stdout.strip(), "NEW-PHONE")

    def test_simulators_unreachable_phones_and_other_devices_are_skipped(self):
        devices = [
            device("SIM", reality="simulated"),
            device("GONE", tunnel="unavailable"),
            device("IPAD", device_type="iPad"),
            device("PHONE"),
        ]
        stand_ins = StandIns(self, devices=devices)

        actual = run([CONNECTED], stand_ins.environment())

        self.assertEqual(actual.stdout.strip(), "PHONE")

    def test_no_iphone_fails_saying_so(self):
        stand_ins = StandIns(self, devices=[device("SIM", reality="simulated")])

        actual = run([CONNECTED], stand_ins.environment())

        self.assertEqual(actual.returncode, 1)
        self.assertEqual(actual.stdout, "")
        self.assertIn("No iPhone connected", actual.stderr)


def profile(identifier, devices):
    return plistlib.dumps({"Name": f"iOS Team Provisioning Profile: {identifier}", "ProvisionedDevices": devices})


class ProvisionTests(unittest.TestCase):
    def provision(self, stand_ins, **environment):
        arguments = [PROVISION, "xcode/App.xcodeproj", "App", "com.example.app", "PHONE"]
        return run(arguments, stand_ins.environment(**environment))

    def test_a_profile_that_includes_the_phone_succeeds(self):
        stand_ins = StandIns(self, devices=[device("PHONE")])
        (stand_ins.work / "made.mobileprovision").write_bytes(profile("com.example.app", ["OTHER", "PHONE"]))

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertIn("includes this iPhone (PHONE)", actual.stdout)
        (call,) = stand_ins.calls("xcodebuild-calls")
        self.assertIn("-destination id=PHONE", call)
        self.assertIn("DEVELOPMENT_TEAM=TEAM123", call)

    def test_the_teams_wildcard_profile_that_includes_the_phone_succeeds(self):
        stand_ins = StandIns(self, devices=[device("PHONE")])
        (stand_ins.work / "made.mobileprovision").write_bytes(profile("*", ["PHONE"]))

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertIn('"iOS Team Provisioning Profile: *" includes this iPhone (PHONE)', actual.stdout)

    def test_another_apps_profile_that_includes_the_phone_fails(self):
        stand_ins = StandIns(self, devices=[device("PHONE")])
        (stand_ins.work / "made.mobileprovision").write_bytes(profile("com.example.other", ["PHONE"]))

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 1)
        self.assertIn("No provisioning profile includes this iPhone (PHONE)", actual.stderr)

    def test_developer_mode_off_is_reported_without_building(self):
        stand_ins = StandIns(self, devices=[device("PHONE", developer_mode="disabled")])

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 1)
        self.assertIn("Developer Mode is off", actual.stderr)
        self.assertEqual(stand_ins.calls("xcodebuild-calls"), [])

    def test_xcodebuild_naming_developer_mode_is_reported_as_developer_mode(self):
        stand_ins = StandIns(self, devices=[device("PHONE", developer_mode=None)])
        (stand_ins.work / "xcodebuild-output").write_text("error: To use PHONE for development, enable Developer Mode in Settings.\n")

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 1)
        self.assertIn("Developer Mode is off", actual.stderr)

    def test_a_profile_without_the_phone_fails_showing_xcodebuilds_errors(self):
        stand_ins = StandIns(self, devices=[device("PHONE")])
        (stand_ins.work / "made.mobileprovision").write_bytes(profile("com.example.app", ["OTHER"]))
        (stand_ins.work / "xcodebuild-output").write_text("note: something\nerror: No Account for Team \"TEAM123\".\n")

        actual = self.provision(stand_ins, DEVELOPMENT_TEAM="TEAM123")

        self.assertEqual(actual.returncode, 1)
        self.assertIn('error: No Account for Team "TEAM123".', actual.stderr)
        self.assertIn("No provisioning profile includes this iPhone (PHONE)", actual.stderr)

    def test_no_team_fails_saying_where_one_comes_from(self):
        stand_ins = StandIns(self, devices=[device("PHONE")])

        actual = self.provision(stand_ins)

        self.assertEqual(actual.returncode, 1)
        self.assertIn("set DEVELOPMENT_TEAM", actual.stderr)
        self.assertEqual(stand_ins.calls("xcodebuild-calls"), [])


class SigningProfileTests(unittest.TestCase):
    def signing_profile(self, stand_ins, *profiles, udid="PHONE"):
        directory = stand_ins.home / "Library/MobileDevice/Provisioning Profiles"
        directory.mkdir(parents=True)
        for index, contents in enumerate(profiles):
            (directory / f"{index}.mobileprovision").write_bytes(contents)
        return run([SIGNING_PROFILE, "com.example.app", udid], stand_ins.environment())

    def test_the_bundle_identifiers_profile_that_includes_the_phone_is_app(self):
        stand_ins = StandIns(self)

        actual = self.signing_profile(stand_ins, profile("com.example.app", ["PHONE"]))

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(actual.stdout, "app\n")

    def test_the_wildcard_profile_that_includes_the_phone_is_wildcard(self):
        stand_ins = StandIns(self)

        actual = self.signing_profile(stand_ins, profile("*", ["OTHER", "PHONE"]))

        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(actual.stdout, "wildcard\n")

    def test_the_bundle_identifiers_profile_comes_first_when_both_include_the_phone(self):
        stand_ins = StandIns(self)

        actual = self.signing_profile(stand_ins, profile("*", ["PHONE"]), profile("com.example.app", ["PHONE"]))

        self.assertEqual(actual.stdout, "app\n")

    def test_the_wildcard_profile_is_taken_when_the_bundle_identifiers_lacks_the_phone(self):
        stand_ins = StandIns(self)

        actual = self.signing_profile(stand_ins, profile("com.example.app", ["OTHER"]), profile("*", ["PHONE"]))

        self.assertEqual(actual.stdout, "wildcard\n")

    def test_no_profile_that_includes_the_phone_fails_naming_phone_provision(self):
        stand_ins = StandIns(self)

        actual = self.signing_profile(stand_ins, profile("com.example.other", ["PHONE"]), profile("*", ["OTHER"]))

        self.assertEqual(actual.returncode, 1)
        self.assertEqual(actual.stdout, "")
        self.assertIn("No provisioning profile includes this iPhone (PHONE). Run just phone-provision first.", actual.stderr)

    def test_without_a_udid_the_connected_iphone_is_used(self):
        stand_ins = StandIns(self, devices=[device("SIM", reality="simulated"), device("PHONE")])
        directory = stand_ins.home / "Library/MobileDevice/Provisioning Profiles"
        directory.mkdir(parents=True)
        (directory / "wildcard.mobileprovision").write_bytes(profile("*", ["PHONE"]))

        actual = run([SIGNING_PROFILE, "com.example.app"], stand_ins.environment())

        self.assertEqual(actual.stdout, "wildcard\n")


if __name__ == "__main__":
    unittest.main()
