#!/usr/bin/env python3
"""Tests of template.py's add and remove, against a copy of this checkout committed in a scratch repository.

    python3 template_test.py

Each test makes a project the way bootstrap.sh would (a render, its generated files, a stamp, one
commit), changes it the way an owner might, runs template.py from the copy, and compares the result
with a fresh render. The copy includes uncommitted changes, so the tests check the working tree.
Like template.py, this file stays behind: bootstrap.sh leaves it out of projects.
"""
import importlib.util
import io
import contextlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

TEMPLATE = pathlib.Path(__file__).resolve().parent
NAME = "Demo"
# A line in AGENTS.md's placeholder paragraph, far from what any option marks, and what a project
# writes there instead.
PLACEHOLDER = "<One paragraph: what Demo is, what it optimizes for, who uses it.>"
DESCRIPTION = "Demo greets people, quickly, for the people who need greeting."


def run(*command, cwd):
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True)


def git(*args, cwd):
    result = run("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args, cwd=cwd)
    assert result.returncode == 0, f"git {' '.join(args)}: {result.stderr}"
    return result.stdout.strip()


def tree(root):
    """Every file under `root` but git's and the stamp, by path, as bytes."""
    return {path.relative_to(root).as_posix(): path.read_bytes()
            for path in root.rglob("*")
            if path.is_file() and ".git" not in path.relative_to(root).parts and path.name != ".template.json"}


class TemplateCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = pathlib.Path(tempfile.mkdtemp(prefix="template-test-"))
        cls.template = cls.scratch / "ProjectTemplate"
        listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", cwd=TEMPLATE).split("\0")
        for relative in filter(None, listed):
            source = TEMPLATE / relative
            if source.is_file() and not source.is_symlink():
                destination = cls.template / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
        git("init", "-q", "-b", "main", cwd=cls.template)
        git("add", "-A", cwd=cls.template)
        git("commit", "-q", "-m", "template", cwd=cls.template)
        cls.commit = git("rev-parse", "HEAD", cwd=cls.template)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.scratch)

    def render(self, directory, *flags):
        """The template rendered with `flags`, with the files scripts/modules.py generates."""
        result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", *flags, NAME, str(directory),
                     cwd=self.scratch)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = run(sys.executable, "scripts/modules.py", cwd=directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        return directory

    def project(self, label, stamp, *flags):
        """A committed project rendered with `flags`, stamped with `stamp`'s options."""
        directory = self.render(self.scratch / label, *flags)
        stamp = {"commit": self.commit, "name": NAME, "type": "library", "benchmarks": False, "mutation": False,
                 "fuzz": False, "differential": False, "wasm": False, "explore": False, "views": False,
                 "examples": False, "performance": False, "fly": False, "database": False, "ci": True, "trunk": False,
                 **stamp}
        (directory / ".template.json").write_text(json.dumps(stamp, indent=2) + "\n")
        git("init", "-q", "-b", "main", cwd=directory)
        git("add", "-A", cwd=directory)
        git("commit", "-q", "-m", "project", cwd=directory)
        return directory

    def own_edits(self, project):
        """The project's own changes, committed: its description and a module of its own."""
        agents = project / "AGENTS.md"
        agents.write_text(agents.read_text().replace(PLACEHOLDER, DESCRIPTION))
        own = project / "Sources" / "Greetings" / "Farewell.swift"
        own.write_text("public let farewell = \"Goodbye\"\n")
        git("add", "-A", cwd=project)
        git("commit", "-q", "-m", "own edits", cwd=project)

    def template_py(self, *args):
        return run(sys.executable, str(self.template / "template.py"), *args, cwd=self.scratch)

    def test_remove_wasm_gives_a_fresh_render_without_it_plus_the_project_edits(self):
        project = self.project("remove-wasm", {"wasm": True}, "--library", "--wasm")
        self.own_edits(project)
        expected = self.render(self.scratch / "expected-no-wasm", "--library")
        agents = expected / "AGENTS.md"
        agents.write_text(agents.read_text().replace(PLACEHOLDER, DESCRIPTION))
        (expected / "Sources" / "Greetings" / "Farewell.swift").write_text("public let farewell = \"Goodbye\"\n")
        expected_commits = git("rev-list", "--count", "HEAD", cwd=project)

        result = self.template_py("remove", str(project), "--wasm")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual, wanted = tree(project), tree(expected)
        self.assertEqual(sorted(actual), sorted(wanted))
        for path in sorted(wanted):
            self.assertEqual(actual[path], wanted[path], path)
        stamp = json.loads((project / ".template.json").read_text())
        self.assertFalse(stamp["wasm"])
        self.assertEqual(stamp["commit"], self.commit)
        self.assertEqual(git("rev-list", "--count", "HEAD", cwd=project), expected_commits)
        self.assertTrue(git("status", "--porcelain", cwd=project))

    def test_remove_wasm_keeps_what_the_explorer_still_builds_for_wasi(self):
        project = self.project("remove-wasm-explore", {"wasm": True, "explore": True}, "--library", "--wasm", "--explore")
        expected = self.render(self.scratch / "expected-explore", "--library", "--explore")

        result = self.template_py("remove", str(project), "--wasm")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual, wanted = tree(project), tree(expected)
        self.assertEqual(sorted(actual), sorted(wanted))
        for path in sorted(wanted):
            self.assertEqual(actual[path], wanted[path], path)
        self.assertIn("NON_WASI_PACKAGES = []", (project / "scripts" / "modules.py").read_text())
        self.assertFalse((project / "scripts" / "wasi_test.py").exists())

    def test_remove_refuses_an_option_the_stamp_lacks_and_changes_nothing(self):
        project = self.project("remove-absent", {}, "--library")
        expected_stamp = (project / ".template.json").read_text()

        result = self.template_py("remove", str(project), "--wasm")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("doesn't have --wasm", result.stderr)
        self.assertEqual(git("status", "--porcelain", cwd=project), "")
        self.assertEqual((project / ".template.json").read_text(), expected_stamp)

    def test_remove_refuses_ci_while_trunk_stays_on(self):
        project = self.project("remove-ci", {"trunk": True}, "--library", "--trunk")

        result = self.template_py("remove", str(project), "--ci")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("remove --trunk with it", result.stderr)
        self.assertEqual(git("status", "--porcelain", cwd=project), "")

    def test_add_wasm_gives_a_fresh_render_with_it_plus_the_project_edits(self):
        project = self.project("add-wasm", {}, "--library")
        self.own_edits(project)
        expected = self.render(self.scratch / "expected-wasm", "--library", "--wasm")
        agents = expected / "AGENTS.md"
        agents.write_text(agents.read_text().replace(PLACEHOLDER, DESCRIPTION))
        (expected / "Sources" / "Greetings" / "Farewell.swift").write_text("public let farewell = \"Goodbye\"\n")

        result = self.template_py("add", str(project), "--wasm")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual, wanted = tree(project), tree(expected)
        self.assertEqual(sorted(actual), sorted(wanted))
        for path in sorted(wanted):
            self.assertEqual(actual[path], wanted[path], path)
        self.assertTrue(json.loads((project / ".template.json").read_text())["wasm"])

    def test_add_ios_to_a_server_gives_a_fresh_render_with_it_plus_the_project_edits(self):
        project = self.project("add-ios", {"type": "server"}, "--server")
        self.own_edits(project)
        expected = self.render(self.scratch / "expected-ios", "--server", "--ios")
        agents = expected / "AGENTS.md"
        agents.write_text(agents.read_text().replace(PLACEHOLDER, DESCRIPTION))
        (expected / "Sources" / "Greetings" / "Farewell.swift").write_text("public let farewell = \"Goodbye\"\n")

        result = self.template_py("add", str(project), "--ios")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual, wanted = tree(project), tree(expected)
        self.assertEqual(sorted(actual), sorted(wanted))
        for path in sorted(wanted):
            self.assertEqual(actual[path], wanted[path], path)
        self.assertIn("Apps/Demo/BUILD.bazel", actual)
        self.assertIn("tools/test_host/BUILD.bazel", actual)
        self.assertIn("tools/ios.bzl", actual)
        self.assertTrue(json.loads((project / ".template.json").read_text())["ios"])

    def test_add_simulator_to_a_library_gives_a_fresh_render_with_it_plus_the_project_edits(self):
        project = self.project("add-simulator", {}, "--library")
        self.own_edits(project)
        expected = self.render(self.scratch / "expected-simulator", "--library", "--simulator")
        agents = expected / "AGENTS.md"
        agents.write_text(agents.read_text().replace(PLACEHOLDER, DESCRIPTION))
        (expected / "Sources" / "Greetings" / "Farewell.swift").write_text("public let farewell = \"Goodbye\"\n")

        result = self.template_py("add", str(project), "--simulator")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual, wanted = tree(project), tree(expected)
        self.assertEqual(sorted(actual), sorted(wanted))
        for path in sorted(wanted):
            self.assertEqual(actual[path], wanted[path], path)
        self.assertIn("tools/test_host/BUILD.bazel", actual)
        self.assertIn("tools/ios.bzl", actual)
        self.assertIn(b"--local_resources=simulator=1", actual[".bazelrc"])
        self.assertFalse(any(path.startswith("Apps/") for path in actual))
        stamp = json.loads((project / ".template.json").read_text())
        self.assertTrue(stamp["simulator"])
        self.assertFalse(stamp.get("ios", False))

    def test_simulator_comes_with_ios_so_add_and_remove_leave_it_to_ios(self):
        project = self.project("simulator-with-ios", {"ios": True}, "--library", "--ios")

        added = self.template_py("add", str(project), "--simulator")
        both = dict(json.loads((project / ".template.json").read_text()), simulator=True)
        (project / ".template.json").write_text(json.dumps(both, indent=2) + "\n")
        git("commit", "-q", "-am", "stamp both", cwd=project)
        removed = self.template_py("remove", str(project), "--simulator")

        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("already has --simulator", added.stdout)
        self.assertNotEqual(removed.returncode, 0)
        self.assertIn("--ios brings --simulator's files too", removed.stderr)
        self.assertEqual(git("status", "--porcelain", cwd=project), "")

    def test_add_simulator_refuses_a_type_it_doesnt_apply_to(self):
        project = self.project("add-simulator-mcp", {"type": "mcp"}, "--mcp")

        result = self.template_py("add", str(project), "--simulator")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--simulator doesn't apply to the mcp type", result.stderr)

    def test_add_skips_a_file_the_option_adds_to_a_sample_module_the_project_removed(self):
        project = self.project("add-performance-without-greetings", {}, "--library")
        shutil.rmtree(project / "Sources" / "Greetings")
        shutil.rmtree(project / "Tests" / "GreetingsTests")
        git("add", "-A", cwd=project)
        git("commit", "-q", "-m", "the Greetings sample replaced", cwd=project)

        result = self.template_py("add", str(project), "--performance")

        self.assertIn("Tests/GreetingsTests/GreetingExitTests.swift (the template added it to Tests/GreetingsTests, "
                      "which this project removed)", result.stdout)
        # scripts/modules.py still lists Greetings here, so its generated files (BUILD.bazel, a stub
        # source) return; none of the template's own does.
        self.assertFalse((project / "Tests" / "GreetingsTests" / "GreetingExitTests.swift").exists())
        self.assertFalse((project / "Sources" / "Greetings" / "Greeting.swift").exists())

    def test_add_installs_a_file_the_option_adds_to_a_kept_directory_or_a_new_one(self):
        project = self.project("add-performance-and-benchmarks", {}, "--library")
        shutil.rmtree(project / "Sources" / "Greetings")
        git("add", "-A", cwd=project)
        git("commit", "-q", "-m", "the Greetings module replaced, its tests kept", cwd=project)

        performance = self.template_py("add", str(project), "--performance")
        git("add", "-A", cwd=project)
        git("commit", "-q", "-m", "performance", cwd=project)
        benchmarks = self.template_py("add", str(project), "--benchmarks")

        self.assertIn("Tests/GreetingsTests/GreetingExitTests.swift", performance.stdout)
        self.assertNotIn("which this project removed", performance.stdout)
        self.assertTrue((project / "Tests" / "GreetingsTests" / "GreetingExitTests.swift").is_file())
        self.assertNotIn("which this project removed", benchmarks.stdout)
        self.assertTrue((project / "Benchmarks" / "Package.swift").is_file())

    def test_add_ios_reports_what_the_project_had_already_copied_by_hand_as_duplicates(self):
        project = self.project("add-ios-by-hand", {"type": "server"}, "--server")
        load = 'load("//tools:ios.bzl", "IOS_PACKAGES", "SIMULATOR_TEST_PACKAGES")'
        build = project / "BUILD.bazel"
        build.write_text(load + "\n" + build.read_text())
        justfile = project / "justfile"
        justfile.write_text(justfile.read_text() + "\n[doc('Launch the iOS app')]\nrun-app:\n    {{BAZEL}} run //Apps/Demo\n")
        git("commit", "-q", "-am", "iOS pieces copied by hand", cwd=project)

        result = self.template_py("add", str(project), "--ios")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("DUPLICATES", result.stdout)
        self.assertIn(f"BUILD.bazel: {load}", result.stdout)
        self.assertIn("justfile: run-app:", result.stdout)
        self.assertIn("justfile: {{BAZEL}} run //Apps/Demo", result.stdout)
        self.assertEqual(build.read_text().count(load), 2)

    # The bullets every variant of AGENTS.md's Errors section keeps word for word.
    INVARIANT_BULLETS = (
        "- **Invariant-breaking mutations throw on the plain spelling** and change nothing, with one typed\n"
        "  error per invariant whose cases make a single `catch` exhaustive.\n"
        "- **Queries whose failure is the answer return a witness** (`findCycle() -> Cycle?`), not an\n"
        "  error.\n")
    TRAP_BULLETS = (
        "- **Plain spellings trap** on a precondition failure, like an `Array` subscript. They are the\n"
        "  fast path.\n"
        "- **`checked:` spellings throw** a typed, payload-free error (`Greeting(checkedName:)` throws\n"
        "  `EmptyName`). There are no nil-returning variants; `try?` gives `nil`.\n")

    def test_a_library_without_performance_throws_where_it_can_fail_and_never_traps(self):
        directory = self.render(self.scratch / "throwing-library", "--library")

        agents = (directory / "AGENTS.md").read_text()
        greeting = (directory / "Sources" / "Greetings" / "Greeting.swift").read_text()

        for phrase in ("checked:", "Plain spellings trap", "exit tests for every trap", "Performance patterns"):
            self.assertNotIn(phrase, agents)
        self.assertIn("- **Everything that can fail throws** a typed, payload-free error from its one spelling", agents)
        self.assertIn("`--performance`", agents)
        self.assertIn("   - every error the code throws, each from the input that causes it;\n", agents)
        self.assertIn("Their conventions carry over: value types, typed errors, tests with Swift Testing.\n", agents)
        self.assertIn("### Errors\n\n- **Everything that can fail throws**", agents)
        self.assertIn(self.INVARIANT_BULLETS, agents)
        self.assertIn("public init(name: String) throws(EmptyName) {", greeting)
        for absent in ("checkedName", "precondition(", "@inlinable", "@frozen"):
            self.assertNotIn(absent, greeting)
        self.assertFalse((directory / "Tests" / "GreetingsTests" / "GreetingExitTests.swift").exists())
        self.assertNotIn("precondition", (directory / "Tests" / "DemoTestSupport" / "Tags.swift").read_text())

    def test_a_library_with_performance_keeps_trap_and_checked_spellings_and_the_performance_patterns(self):
        directory = self.render(self.scratch / "performance-library", "--library", "--performance")
        template_agents = git("show", "HEAD~0:AGENTS.md", cwd=self.template)

        agents = (directory / "AGENTS.md").read_text()
        greeting = (directory / "Sources" / "Greetings" / "Greeting.swift").read_text()

        self.assertIn("### Errors\n\n" + self.TRAP_BULLETS + self.INVARIANT_BULLETS, agents)
        self.assertIn("   - `checked:` spellings and their errors;\n   - exit tests for every trap;\n", agents)
        self.assertIn("Their conventions carry over: value types, typed errors, `checked:` spellings that throw where\n"
                      "the plain spelling traps, tests with Swift Testing.\n", agents)
        self.assertIn('("The checked spelling throws EmptyName for an empty name")', agents)
        self.assertNotIn("Everything that can fail throws", agents)
        patterns = agents[agents.index("### Performance patterns"):]
        self.assertIn("- Write overflow guards as comparisons (`x <= Int.max / 4`), not a discarded\n"
                      "  `multipliedReportingOverflow` result.\n", patterns)
        self.assertTrue(agents.endswith("`multipliedReportingOverflow` result.\n"))
        self.assertNotIn("performance:", agents)
        self.assertIn("### Performance patterns", template_agents)
        self.assertIn('precondition(!name.isEmpty, "A greeting needs a name")', greeting)
        self.assertIn("public init(checkedName name: String) throws(EmptyName) {", greeting)
        self.assertTrue((directory / "Tests" / "GreetingsTests" / "GreetingExitTests.swift").is_file())

    def test_performance_is_refused_for_a_type_that_doesnt_take_it(self):
        refused = {}
        for kind in ("mcp", "app", "embedded"):
            result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", f"--{kind}", "--performance",
                         NAME, str(self.scratch / f"performance-{kind}"), cwd=self.scratch)
            refused[kind] = (result.returncode != 0, "--performance applies to the library and server types only" in result.stderr)
        project = self.project("add-performance-mcp", {"type": "mcp"}, "--mcp")

        added = self.template_py("add", str(project), "--performance")

        self.assertEqual(refused, {kind: (True, True) for kind in refused})
        self.assertNotEqual(added.returncode, 0)
        self.assertIn("--performance doesn't apply to the mcp type", added.stderr)

    def test_update_notes_the_throwing_default_once_for_a_library_or_server_stamped_before_performance(self):
        notes = {}
        stamps = {}
        for kind in ("library", "server", "mcp"):
            project = self.project(f"update-before-performance-{kind}", {"type": kind}, f"--{kind}")
            path = project / ".template.json"
            stamp = json.loads(path.read_text())
            del stamp["performance"]
            path.write_text(json.dumps(stamp, indent=2) + "\n")
            git("commit", "-q", "-am", "a stamp from before --performance", cwd=project)
            readme = self.template / "README.md"
            readme.write_text(readme.read_text() + "\nA later template change.\n")
            git("commit", "-q", "-am", "later", cwd=self.template)
            try:
                first = self.template_py("update", str(project))
                git("add", "-A", cwd=project)
                git("commit", "-q", "-m", "update", cwd=project)
                readme.write_text(readme.read_text() + "\nAnother.\n")
                git("commit", "-q", "-am", "later still", cwd=self.template)
                second = self.template_py("update", str(project))
            finally:
                git("reset", "-q", "--hard", self.commit, cwd=self.template)
            notes[kind] = ("stamp predates --performance" in first.stderr, "stamp predates --performance" in second.stderr)
            stamps[kind] = json.loads(path.read_text()).get("performance")
            if kind == "library":
                self.assertIn("renders the throwing error convention by default", first.stderr)
                self.assertIn(f"./template.py add {project.resolve()} --performance", first.stderr)

        self.assertEqual(notes, {"library": (True, False), "server": (True, False), "mcp": (False, False)})
        self.assertEqual(stamps, {"library": False, "server": False, "mcp": None})

    def test_a_render_leaves_out_the_templates_own_readme_and_docs(self):
        directory = self.render(self.scratch / "own-docs", "--library")

        actual = tree(directory)

        self.assertIn(".github/workflows/CI.yml", actual)
        self.assertNotIn(".github/README.md", actual)
        self.assertEqual([path for path in actual if path.startswith(".github/docs/")], [])

    def test_a_missing_buildbuddy_key_warns_in_both_workflows_and_leaves_the_build_uncached(self):
        directory = self.render(self.scratch / "buildbuddy-warning", "--library")
        expected_warning = ("::warning::BUILDBUDDY_API_KEY is not set; Bazel runs without the remote cache "
                            "(run just ci-secrets)")

        for workflow in ("CI.yml", "docc.yml"):
            lines = (directory / ".github" / "workflows" / workflow).read_text().splitlines()
            start = lines.index("      - name: Configure the remote cache")
            run_line = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |")
            body = []
            for line in lines[run_line + 1:]:
                if line.strip() and not line.startswith(" " * 10):
                    break
                body.append(line[10:])
            script = "\n".join(body) + "\n"
            for key in ("", "secret-key"):
                with self.subTest(workflow=workflow, key=bool(key)):
                    home = pathlib.Path(tempfile.mkdtemp(dir=self.scratch))
                    environment = {**os.environ, "HOME": str(home), "BUILDBUDDY_API_KEY": key}

                    result = subprocess.run(["bash", "-e", "-c", script], cwd=home, env=environment,
                                            capture_output=True, text=True)

                    actual = (home / "user.bazelrc").read_text()
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if key:
                        self.assertNotIn("::warning::", result.stdout)
                        self.assertIn("build --remote_cache=grpcs://remote.buildbuddy.io", actual)
                        self.assertIn("common --remote_header=x-buildbuddy-api-key=secret-key", actual)
                    else:
                        self.assertEqual(result.stdout.strip(), expected_warning)
                        self.assertNotIn("remote_cache=", actual)
                        self.assertNotIn("buildbuddy", actual)

    def test_a_render_without_ci_has_no_workflows(self):
        directory = self.render(self.scratch / "no-ci-workflows", "--library", "--no-ci")

        actual = tree(directory)

        self.assertEqual([path for path in actual if path.startswith(".github/workflows/")], [])

    def test_a_library_names_every_apple_sdk_once_and_other_types_name_none(self):
        expected_sdks = ["AppleTVOS", "AppleTVSimulator", "MacOSX", "WatchOS", "WatchSimulator", "XROS",
                         "XRSimulator", "iPhoneOS", "iPhoneSimulator"]
        found = {}

        for flags in (["--library"], ["--library", "--examples"], ["--server"], ["--mcp"], ["--embedded"], ["--app"]):
            directory = self.scratch / ("sdks" + "".join(flags))
            result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", *flags, NAME, str(directory),
                         cwd=self.scratch)
            self.assertEqual(result.returncode, 0, result.stderr)
            module = (directory / "MODULE.bazel").read_text()
            calls = re.findall(r"system_sdk\.configure_sdks\(names = \[(.*?)\]\)", module, re.DOTALL)
            found[" ".join(flags)] = [sorted(re.findall(r'"(\w+)"', call)) for call in calls]

        expected_library = [sorted(expected_sdks)]
        self.assertEqual(found, {"--library": expected_library, "--library --examples": expected_library,
                                 "--server": [], "--mcp": [], "--embedded": [], "--app": []})

    def test_a_render_leaves_out_the_template_only_ignore_line_and_ends_on_content(self):
        found = {}

        for flags in (["--library"], ["--library", "--explore", "--wasm"], ["--embedded"]):
            directory = self.scratch / ("ignore" + "".join(flags))
            result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", *flags, NAME, str(directory),
                         cwd=self.scratch)
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = (directory / ".bazelignore").read_text().split("\n")
            # (has the line, ends on a blank line), as split leaves "" after the final newline.
            found[" ".join(flags)] = ("templates" in lines, lines[-2] == "")

        self.assertEqual(found, {name: (False, False) for name in found})
        self.assertIn("templates", (self.template / ".bazelignore").read_text().split("\n"))

    def test_update_notes_template_changes_only_for_tracked_files(self):
        project = self.project("update-untracked", {}, "--library")
        untracked = self.template / ".kanban" / "board.json"
        readme = self.template / "README.md"
        original = readme.read_text()
        untracked.parent.mkdir(exist_ok=True)
        untracked.write_text("{}\n")
        note = "the template has uncommitted changes"
        try:
            with_untracked = self.template_py("update", str(project))
            readme.write_text(original + "\nA tracked change.\n")
            with_tracked = self.template_py("update", str(project))
        finally:
            readme.write_text(original)
            shutil.rmtree(untracked.parent)

        self.assertNotIn(note, with_untracked.stderr)
        self.assertIn(note, with_tracked.stderr)

    def test_update_notes_an_option_whose_files_the_project_has_but_its_stamp_lacks_and_still_updates(self):
        project = self.project("update-unstamped-fuzz", {}, "--library", "--fuzz")
        readme = self.template / "README.md"
        readme.write_text(readme.read_text() + "\nA later template change.\n")
        git("commit", "-q", "-am", "later", cwd=self.template)
        later = git("rev-parse", "HEAD", cwd=self.template)
        try:
            result = self.template_py("update", str(project))
        finally:
            git("reset", "-q", "--hard", self.commit, cwd=self.template)
        stamp = json.loads((project / ".template.json").read_text())

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("has the files of --fuzz, but its stamp has it off", result.stderr)
        self.assertIn(f"./template.py stamp {project.resolve()} --type library --fuzz --name {NAME} "
                      f"--commit {self.commit[:12]}", result.stderr)
        self.assertIn(f"./template.py add {project.resolve()} --fuzz", result.stderr)
        self.assertEqual(stamp["commit"], later)
        self.assertFalse(stamp["fuzz"])
        self.assertIn("A later template change.", (project / "README.md").read_text())
        self.assertTrue((project / "Fuzz").is_dir())

    def test_the_noted_stamp_command_records_the_option_and_status_flags_it_until_then(self):
        project = self.project("stamp-unstamped-ios", {"type": "server"}, "--server", "--ios")
        before = self.template_py("status", "--root", str(project.parent))

        restamp = self.template_py("stamp", str(project), "--type", "server", "--ios", "--name", NAME,
                                   "--commit", self.commit)
        after = self.template_py("status", "--root", str(project.parent))
        stamp = json.loads((project / ".template.json").read_text())

        self.assertEqual(restamp.returncode, 0, restamp.stderr)
        self.assertRegex(before.stdout, r"stamp-unstamped-ios .*has --ios --simulator's files, stamped without")
        self.assertNotRegex(after.stdout, r"stamp-unstamped-ios .*stamped without")
        self.assertTrue(stamp["ios"])

    def test_no_option_is_noted_for_a_fresh_render_of_any_type_stamped_as_rendered(self):
        spec = importlib.util.spec_from_file_location("template_under_test", self.template / "template.py")
        template = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(template)
        everywhere = ["benchmarks", "mutation", "fuzz", "differential"]
        every_option = {
            "library": everywhere + ["wasm", "explore", "views", "examples", "ios", "simulator", "performance", "trunk"],
            "server": everywhere + ["ios", "simulator", "performance", "fly", "database", "trunk"],
            "embedded": everywhere + ["wasm", "trunk"],
            "mcp": everywhere + ["trunk"],
            "app": everywhere,
        }
        found = {}

        for kind, chosen in every_option.items():
            for label, on in (("plain", []), ("every-option", chosen)):
                directory = self.scratch / f"fresh-{kind}-{label}"
                result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", f"--{kind}",
                             *(f"--{feature}" for feature in on), NAME, str(directory), cwd=self.scratch)
                self.assertEqual(result.returncode, 0, result.stderr)
                stamp = {"commit": self.commit, "name": NAME, "type": kind,
                         **{feature: feature in on for feature in template.FEATURES if feature != "ci"},
                         "ci": kind != "app"}
                found[f"{kind} {label}"] = template.unstamped_options(directory, stamp)

        self.assertEqual(found, {name: [] for name in found})

    def test_an_own_file_spelled_like_an_options_in_another_case_or_an_own_directory_is_not_noted(self):
        spec = importlib.util.spec_from_file_location("template_under_test", self.template / "template.py")
        template = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(template)
        directory = self.scratch / "own-workflow"
        (directory / ".github" / "workflows").mkdir(parents=True)
        (directory / ".github" / "workflows" / "ci.yml").write_text("name: ci\n")
        (directory / "Examples" / "Bootstrap").mkdir(parents=True)
        stamp = {"commit": self.commit, "name": NAME, "type": "library", "ci": False}

        actual = template.unstamped_options(directory, stamp)

        self.assertEqual(actual, [])

    def test_an_unstamped_option_the_stamped_commit_lacks_is_noted_as_update_then_add_not_stamp(self):
        bootstrap = self.template / "bootstrap.sh"
        original = bootstrap.read_text()
        bootstrap.write_text(original.replace("--simulator)", "--simulator-not-yet)"))
        git("commit", "-q", "-am", "before --simulator", cwd=self.template)
        before = git("rev-parse", "HEAD", cwd=self.template)
        bootstrap.write_text(original)
        git("commit", "-q", "-am", "--simulator", cwd=self.template)
        arrived = git("rev-parse", "HEAD", cwd=self.template)
        project = self.project("unstamped-too-old", {"commit": before}, "--library", "--simulator")
        try:
            result = self.template_py("update", str(project), "--to", before)
        finally:
            git("reset", "-q", "--hard", self.commit, cwd=self.template)

        self.assertIn("has the files of --simulator", result.stderr)
        self.assertNotIn("template.py stamp", result.stderr)
        self.assertIn(f"has no --simulator (from {arrived[:12]})", result.stderr)
        self.assertIn(f"./template.py update {project.resolve()} --to {arrived[:12]}", result.stderr)
        self.assertIn(f"./template.py add {project.resolve()} --simulator", result.stderr)

    def test_an_unstamped_option_the_stamped_commit_has_is_still_noted_as_stamp_or_add(self):
        project = self.project("unstamped-known", {}, "--library", "--simulator")

        result = self.template_py("update", str(project))

        self.assertIn(f"./template.py stamp {project.resolve()} --type library --simulator --name {NAME} "
                      f"--commit {self.commit[:12]}", result.stderr)
        self.assertIn(f"./template.py add {project.resolve()} --simulator", result.stderr)
        self.assertNotIn("can't be stamped or added there", result.stderr)

    def bootstrap_stamp(self, label):
        """A full bootstrap.sh run of a library into the scratch directory, with a stand-in `just` so it
        neither resolves nor tests; returns the stamp it wrote."""
        stand_ins = self.scratch / "stand-ins"
        stand_ins.mkdir(exist_ok=True)
        just = stand_ins / "just"
        just.write_text("#!/bin/sh\nexit 0\n")
        just.chmod(0o755)
        destination = self.scratch / label
        environment = dict(os.environ, PATH=f"{stand_ins}{os.pathsep}{os.environ['PATH']}")
        result = subprocess.run(["bash", str(self.template / "bootstrap.sh"), "--library", "--yes", NAME, str(destination)],
                                cwd=self.scratch, capture_output=True, text=True, env=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads((destination / ".template.json").read_text())

    def test_bootstrap_stamps_modified_for_changes_that_reach_the_project_alone(self):
        left_out = self.template / ".kanban" / "board.json"
        copied = self.template / "PROBE.md"
        readme = self.template / "README.md"
        original = readme.read_text()
        left_out.parent.mkdir(exist_ok=True)
        left_out.write_text("{}\n")
        try:
            with_left_out = self.bootstrap_stamp("stamp-left-out")
            copied.write_text("probe\n")
            with_copied = self.bootstrap_stamp("stamp-copied")
            copied.unlink()
            readme.write_text(original + "\nA tracked change.\n")
            with_tracked = self.bootstrap_stamp("stamp-tracked")
        finally:
            readme.write_text(original)
            copied.unlink(missing_ok=True)
            shutil.rmtree(left_out.parent)

        self.assertNotIn("modified", with_left_out)
        self.assertTrue(with_copied.get("modified"))
        self.assertTrue(with_tracked.get("modified"))

    def test_a_conflicted_modules_py_is_reported_as_markers_to_resolve_not_a_traceback(self):
        spec = importlib.util.spec_from_file_location("template_under_test", self.template / "template.py")
        template = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(template)
        report = {name: [] for name in ("updated", "added", "removed", "merged", "conflicted", "duplicated",
                                        "kept", "skipped", "regenerated")}
        report["conflicted"].append("scripts/modules.py")
        failed = subprocess.CompletedProcess([], 1, "", 'Traceback (most recent call last):\n  File "scripts/modules.py", line 9\n    <<<<<<< project\nSyntaxError: invalid syntax\n')
        printed = io.StringIO()

        with contextlib.redirect_stdout(printed):
            status = template.print_report(report, failed)

        self.assertEqual(status, 1)
        self.assertIn("scripts/modules.py still holds conflict markers", printed.getvalue())
        self.assertIn("`just modules`", printed.getvalue())
        self.assertNotIn("Traceback", printed.getvalue())
        self.assertNotIn("SyntaxError", printed.getvalue())

    def test_add_ios_refuses_a_type_it_doesnt_apply_to(self):
        project = self.project("add-ios-mcp", {"type": "mcp"}, "--mcp")

        result = self.template_py("add", str(project), "--ios")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--ios doesn't apply to the mcp type", result.stderr)
        self.assertEqual(git("status", "--porcelain", cwd=project), "")

    def test_modules_without_ios_refuses_ios_modules_and_simulator_tests(self):
        directory = self.render(self.scratch / "no-ios", "--server")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()
        cases = [
            (original.replace("IOS_MODULES = []", 'IOS_MODULES = ["Greetings"]', 1), "IOS_MODULES needs tools/ios.bzl"),
            (original.replace('    ("AppTests", ["App", "vapor/VaporTesting"]),',
                              '    ("AppTests", ["App", "vapor/VaporTesting", "//tools/snapshots:BazelSnapshotTesting"]),', 1),
             "AppTests run in the iOS simulator"),
        ]
        for text, expected_message in cases:
            self.assertNotEqual(text, original)
            modules.write_text(text)

            result = run(sys.executable, "scripts/modules.py", cwd=directory)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected_message, result.stderr)
            self.assertIn("./template.py add <project>", result.stderr)
            self.assertIn("--simulator", result.stderr)

    def test_a_simulator_only_test_target_is_incompatible_off_macos(self):
        directory = self.render(self.scratch / "ios-library", "--library", "--ios")
        modules = directory / "scripts" / "modules.py"
        text = modules.read_text()
        modules.write_text(text.replace("IOS_MODULES = []", 'IOS_MODULES = ["Screens"]', 1)
                           .replace("MODULES = [\n", 'MODULES = [\n    ("Screens", "App", "Screens.", ["Greetings"]),\n', 1)
                           .replace("TEST_TARGETS = [\n", 'TEST_TARGETS = [\n    ("ScreensTests", ["Screens"]),\n', 1))
        for path in ("Sources/Screens/Screens.swift", "Tests/ScreensTests/ScreensTests.swift"):
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            (directory / path).write_text("import Foundation\n")

        result = run(sys.executable, "scripts/modules.py", cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        build = (directory / "Tests" / "ScreensTests" / "BUILD.bazel").read_text()
        self.assertIn('"@platforms//os:macos": [],', build.split("ios_unit_test(")[1])
        self.assertIn('"Sources/Screens"', (directory / "tools" / "ios.bzl").read_text())
        self.assertIn('"Tests/ScreensTests"', (directory / "tools" / "ios.bzl").read_text())

    def test_language_features_reach_both_build_systems_merged_with_mocking_and_a_speed_reliant_target_inherits_them(self):
        directory = self.render(self.scratch / "language-features", "--library")
        modules = directory / "scripts" / "modules.py"
        performance = directory / "Tests" / "GreetingsTests" / "Performance"
        performance.mkdir()
        (performance / "GreetingSpeedTests.swift").write_text("import Testing\n")
        modules.write_text(modules.read_text()
                           .replace("EXPERIMENTAL_FEATURES = {}", 'EXPERIMENTAL_FEATURES = {"Greetings": ["Extern"]}', 1)
                           .replace("UPCOMING_FEATURES = {}", 'UPCOMING_FEATURES = {"GreetingsTests": ["ExistentialAny"]}', 1)
                           .replace("PERFORMANCE_TESTS = [\n", 'PERFORMANCE_TESTS = [\n    "GreetingsTests",\n', 1)
                           .replace('    # ("mockable", "https://github.com/Kolos65/Mockable", "0.6.4"),',
                                    '    ("mockable", "https://github.com/Kolos65/Mockable", "0.6.4"),', 1)
                           .replace('"Greetings", "Example", "Greeting: a greeting composed from a name and modifiers. Replace with the first real module.", []',
                                    '"Greetings", "Example", "Greeting: a greeting composed from a name and modifiers. Replace with the first real module.", ["mockable/Mockable"]', 1))
        expected_module = ', swiftSettings: [.define("MOCKING", .when(configuration: .debug)), .enableExperimentalFeature("Extern")]),'
        expected_tests = ', swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),'
        expected_module_copts = '    copts = [\n        "-enable-experimental-feature",\n        "Extern",\n    ],\n'
        expected_tests_copts = '    copts = [\n        "-enable-upcoming-feature",\n        "ExistentialAny",\n    ],\n'

        result = run(sys.executable, "scripts/modules.py", cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = (directory / "Package.swift").read_text().splitlines()
        actual = {name: next(line for line in manifest if f'arget(name: "{name}"' in line)
                  for name in ("Greetings", "GreetingsTests", "GreetingsPerformanceTests")}
        self.assertTrue(actual["Greetings"].endswith(expected_module), actual["Greetings"])
        self.assertTrue(actual["GreetingsTests"].endswith(expected_tests), actual["GreetingsTests"])
        self.assertTrue(actual["GreetingsPerformanceTests"].endswith(expected_tests), actual["GreetingsPerformanceTests"])
        self.assertNotIn("unsafeFlags", "\n".join(manifest))
        self.assertIn(expected_module_copts, (directory / "Sources" / "Greetings" / "BUILD.bazel").read_text())
        tests_build = (directory / "Tests" / "GreetingsTests" / "BUILD.bazel").read_text()
        self.assertEqual(tests_build.count(expected_tests_copts), 2, tests_build)

    def test_check_refuses_a_language_feature_for_an_unknown_target_or_a_malformed_repeated_or_doubled_one(self):
        directory = self.render(self.scratch / "language-feature-checks", "--library")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()

        def generate(experimental, upcoming="{}"):
            modules.write_text(original.replace("EXPERIMENTAL_FEATURES = {}", f"EXPERIMENTAL_FEATURES = {experimental}", 1)
                               .replace("UPCOMING_FEATURES = {}", f"UPCOMING_FEATURES = {upcoming}", 1))
            return run(sys.executable, "scripts/modules.py", cwd=directory).stderr

        actual = {
            "unknown": generate('{"NoSuchModule": ["Extern"]}'),
            "empty": generate('{"Greetings": []}'),
            "malformed": generate('{"Greetings": ["-enable-experimental-feature Extern"]}'),
            "repeated": generate('{"Greetings": ["Extern", "Extern"]}'),
            "doubled": generate('{"Greetings": ["Extern"]}', '{"Greetings": ["Extern"]}'),
        }

        self.assertIn("EXPERIMENTAL_FEATURES names NoSuchModule, which is neither a module nor a test target", actual["unknown"])
        self.assertIn("EXPERIMENTAL_FEATURES gives Greetings no features", actual["empty"])
        self.assertIn("which isn't a feature's name", actual["malformed"])
        self.assertIn("EXPERIMENTAL_FEATURES lists Extern for Greetings more than once", actual["repeated"])
        self.assertIn("Greetings lists Extern as both experimental and upcoming", actual["doubled"])

    def test_a_test_target_lists_fixtures_in_resources_and_check_refuses_unknown_names_and_missing_paths(self):
        directory = self.render(self.scratch / "test-fixtures", "--library")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()
        fixtures = directory / "Tests" / "GreetingsTests" / "Fixtures"
        fixtures.mkdir()
        (fixtures / "sample.json").write_text('{"name":"World"}\n')

        def generate(resources):
            modules.write_text(original.replace("RESOURCES = {}", f"RESOURCES = {resources}", 1))
            return run(sys.executable, "scripts/modules.py", cwd=directory)

        listed = generate('{"GreetingsTests": [("copy", "Fixtures")]}')
        manifest = (directory / "Package.swift").read_text()
        build = (directory / "Tests" / "GreetingsTests" / "BUILD.bazel").read_text()
        unknown = generate('{"NoSuchTests": [("copy", "Fixtures")]}')
        missing = generate('{"GreetingsTests": [("copy", "Missing")]}')

        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertIn('.testTarget(name: "GreetingsTests"', manifest)
        self.assertIn('resources: [.copy("Fixtures")]),', manifest.split('.testTarget(name: "GreetingsTests"')[1].splitlines()[0])
        self.assertIn('srcs = glob(["**/*.swift"]) + [":ResourcesAccessor"],', build)
        self.assertIn('data = module_resources_data("Resources"),', build)
        self.assertIn(f'bundle_name = "{NAME}_GreetingsTests",', build)
        self.assertNotEqual(unknown.returncode, 0)
        self.assertIn("RESOURCES names NoSuchTests, which is neither a module nor a test target", unknown.stderr)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("RESOURCES lists Tests/GreetingsTests/Missing, which doesn't exist", missing.stderr)

    def test_a_generated_source_compiles_the_generators_output_and_check_refuses_a_missing_copy(self):
        directory = self.render(self.scratch / "generated-sources", "--library")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()
        copy = directory / "Sources" / "Greetings" / "Generated" / "Phrases.swift"

        def generate(sources):
            modules.write_text(original.replace("GENERATED_SOURCES = {}", f"GENERATED_SOURCES = {sources}", 1))
            return run(sys.executable, "scripts/modules.py", cwd=directory)

        declared = '{"Greetings": [("Phrases", "//tools:phrases", [], [])]}'
        missing = generate(declared)
        copy.parent.mkdir()
        copy.write_text("")
        listed = generate(declared)
        build = (directory / "Sources" / "Greetings" / "BUILD.bazel").read_text()
        unknown = generate('{"NoSuchModule": [("Phrases", "//tools:phrases", [], [])]}')

        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("GENERATED_SOURCES declares Sources/Greetings/Generated/Phrases.swift, SwiftPM's copy, which doesn't exist",
                      missing.stderr)
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertIn('load("//tools:generated_sources.bzl", "generated_swift_source")', build)
        self.assertIn('generated_swift_source(\n    name = "Phrases",\n    generator = "//tools:phrases",\n', build)
        self.assertIn('srcs = glob(["**/*.swift"], exclude = ["Generated/**"], allow_empty = True) + [":Phrases"],', build)
        self.assertNotEqual(unknown.returncode, 0)
        self.assertIn("GENERATED_SOURCES names NoSuchModule, which is neither a module nor a test target", unknown.stderr)

    def test_a_target_whose_only_sources_are_generated_copies_globs_with_allow_empty(self):
        directory = self.render(self.scratch / "generated-only", "--library")
        modules = directory / "scripts" / "modules.py"
        target = directory / "Tests" / f"{NAME}Tests"
        for source in target.glob("*.swift"):
            source.unlink()
        (target / "Generated").mkdir()
        (target / "Generated" / "Examples.swift").write_text("")
        declared = f'{{"{NAME}Tests": [("Examples", "//tools:examples", [], [])]}}'
        modules.write_text(modules.read_text().replace("GENERATED_SOURCES = {}", f"GENERATED_SOURCES = {declared}", 1))

        result = run(sys.executable, "scripts/modules.py", cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('srcs = glob(["**/*.swift"], exclude = ["Generated/**"], allow_empty = True) + [":Examples"],',
                      (target / "BUILD.bazel").read_text())

    def test_wasi_test_refuses_an_unknown_target_before_building_and_fails_a_target_without_its_runner(self):
        directory = self.render(self.scratch / "wasi-targets", "--library", "--wasm")
        products = directory / "products"
        products.mkdir()
        (products / "GreetingsTests-test-runner.wasm").write_text("")
        probe = ("import sys; sys.path.insert(0, 'scripts'); import wasi_test; "
                 "found = wasi_test.test_binaries('products', ['GreetingsTests', 'ProjectNameTests']); "
                 "print([p.split('/')[-1] for p in found.binaries], found.missing)")

        unknown = run(sys.executable, "scripts/wasi_test.py", "--targets", "GreetingsTests,NoSuchTests", cwd=directory)
        partial = run(sys.executable, "-c", probe.replace("ProjectName", NAME), cwd=directory)

        self.assertEqual(unknown.returncode, 2, unknown.stdout + unknown.stderr)
        self.assertIn("Unknown test targets: NoSuchTests", unknown.stdout)
        self.assertFalse((directory / ".build" / "wasm" / "logs").exists())
        self.assertEqual(partial.returncode, 0, partial.stderr)
        self.assertEqual(partial.stdout.strip(), f"['GreetingsTests-test-runner.wasm'] ['{NAME}Tests']")

    def test_wasi_test_links_its_stack_through_a_toolset_so_no_linker_flag_reaches_a_host_plugin(self):
        directory = self.render(self.scratch / "wasi-toolset", "--library", "--wasm")
        expected = {"schemaVersion": "1.0", "linker": {"extraCLIOptions": ["-z", f"stack-size={64 * 1024 * 1024}"]}}
        probe = "import sys; sys.path.insert(0, 'scripts'); import wasi_test; print(wasi_test.stack_toolset())"

        result = run(sys.executable, "-c", probe, cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        toolset = pathlib.Path(result.stdout.strip())
        self.assertEqual(toolset.resolve(), (directory / ".build" / "wasm" / "stack-toolset.json").resolve())
        self.assertEqual(json.loads(toolset.read_text()), expected)
        self.assertNotIn('"-Xlinker"', (directory / "scripts" / "wasi_test.py").read_text())

    def test_bench_simulated_rewrites_an_entry_measured_over_other_iterations_and_keeps_one_within_the_threshold(self):
        directory = self.render(self.scratch / "bench-iterations", "--library", "--benchmarks")
        spec = importlib.util.spec_from_file_location("bench_simulated_under_test", directory / "scripts" / "bench_simulated.py")
        bench_simulated = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bench_simulated)

        def entry(instructions, iterations, cache_misses):
            # HdrHistogram with 2048 sub-buckets: a value below 1024 sits at its own index.
            def histogram(value):
                return {"subBucketHalfCountMagnitude": 10, "unitMagnitude": 0, "maxValue": value,
                        "counts": [0] * value + [iterations]}
            return [{"metric": {"instructions": {}}, "scalingFactor": 1, "statistics": {"histogram": histogram(instructions)}},
                    {"metric": {"cacheMisses": {}}, "scalingFactor": 1, "statistics": {"histogram": histogram(cache_misses)}}]

        def baseline(**entries):
            results = []
            for name, value in entries.items():
                results += [{"target": "GreetingsBenchmarks", "name": name}, value]
            return {"machine": {}, "results": results}

        recorded = baseline(cold=entry(1000, 1, 900), steady=entry(1000, 3, 900))
        measured = baseline(cold=entry(1000, 3, 300), steady=entry(1010, 3, 300))

        actual = bench_simulated.keep_unmoved(recorded, measured)["results"]

        self.assertEqual(actual[0]["name"], "cold")
        self.assertEqual(actual[1], measured["results"][1])
        self.assertEqual(actual[2]["name"], "steady")
        self.assertEqual(actual[3], recorded["results"][3])

    def test_a_speed_reliant_target_lists_its_own_fixtures_and_check_refuses_one_without_performance_tests(self):
        directory = self.render(self.scratch / "performance-fixtures", "--library")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()
        fixtures = directory / "Tests" / "GreetingsTests" / "Performance" / "Fixtures"
        fixtures.mkdir(parents=True)
        (fixtures / "input.txt").write_text("speed\n")
        (fixtures.parent / "SpeedTests.swift").write_text("import Testing\n")
        listed_tables = original.replace("PERFORMANCE_TESTS = [\n]", 'PERFORMANCE_TESTS = [\n    "GreetingsTests",\n]', 1)

        def generate(tables, resources):
            modules.write_text(tables.replace("RESOURCES = {}", f"RESOURCES = {resources}", 1))
            return run(sys.executable, "scripts/modules.py", cwd=directory)

        listed = generate(listed_tables, '{"GreetingsPerformanceTests": [("copy", "Fixtures")]}')
        manifest = (directory / "Package.swift").read_text()
        build = (directory / "Tests" / "GreetingsTests" / "BUILD.bazel").read_text()
        missing = generate(listed_tables, '{"GreetingsPerformanceTests": [("copy", "Missing")]}')
        unlisted = generate(original, '{"GreetingsPerformanceTests": [("copy", "Fixtures")]}')

        self.assertEqual(listed.returncode, 0, listed.stderr)
        performance_line = manifest.split('.testTarget(name: "GreetingsPerformanceTests"')[1].splitlines()[0]
        self.assertIn('path: "Tests/GreetingsTests/Performance", resources: [.copy("Fixtures")]),', performance_line)
        self.assertIn('srcs = glob(["Performance/**/*.swift"]) + [":PerformanceResourcesAccessor"],', build)
        self.assertIn('data = module_resources_data("PerformanceResources"),', build)
        self.assertIn('    directory = "Performance",\n', build)
        self.assertIn(f'bundle_name = "{NAME}_GreetingsPerformanceTests",', build)
        self.assertNotIn(":ResourcesAccessor", build)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("RESOURCES lists Tests/GreetingsTests/Performance/Missing, which doesn't exist", missing.stderr)
        self.assertNotEqual(unlisted.returncode, 0)
        self.assertIn("no test target in PERFORMANCE_TESTS has a speed-reliant target of that name", unlisted.stderr)

    def test_a_range_version_reaches_both_manifests_and_a_malformed_one_is_refused(self):
        directory = self.render(self.scratch / "range", "--library")
        modules = directory / "scripts" / "modules.py"
        original = modules.read_text()
        row = '    ("swift-syntax", "https://github.com/swiftlang/swift-syntax", "{}"),\n'
        uses = original.replace("PACKAGES = [\n", "PACKAGES = [\n" + row.format("range:603.0.0..<605.0.0"), 1) \
            .replace('("GreetingsTests", ["Greetings", ', '("GreetingsTests", ["Greetings", "swift-syntax/SwiftSyntax", ', 1)
        modules.write_text(uses)
        expected = '.package(url: "https://github.com/swiftlang/swift-syntax", "603.0.0"..<"605.0.0"),'

        result = run(sys.executable, "scripts/modules.py", cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(expected, (directory / "Package.swift").read_text())
        self.assertIn(expected, (directory / "swift" / "Package.swift").read_text())
        for version in ("range:603.0.0", "range:605.0.0..<603.0.0", "range:603..<605.0.0"):
            modules.write_text(uses.replace("range:603.0.0..<605.0.0", version))

            result = run(sys.executable, "scripts/modules.py", cwd=directory)

            self.assertNotEqual(result.returncode, 0, version)
            self.assertIn(f"PACKAGES gives swift-syntax {version!r}", result.stderr)

    def test_a_compiler_plugin_depends_on_a_support_module_in_both_build_systems(self):
        directory = self.render(self.scratch / "plugin-support", "--library")
        modules = directory / "scripts" / "modules.py"
        package = '    ("swift-syntax", "https://github.com/swiftlang/swift-syntax", "range:603.0.0..<605.0.0"),\n'
        modules.write_text(modules.read_text()
                           .replace("PACKAGES = [\n", "PACKAGES = [\n" + package, 1)
                           .replace("MODULES = [\n", 'MODULES = [\n    ("MacroSupport", "Macros", "Expansions plugins share.", ["swift-syntax/SwiftSyntax"]),\n', 1)
                           .replace("MACROS = []", 'MACROS = [("GreetingsMacros", "Macros", "Expands #demo.", ["swift-syntax/SwiftCompilerPlugin", "MacroSupport"])]', 1))
        expected_manifest = '.macro(name: "GreetingsMacros", dependencies: [.product(name: "SwiftCompilerPlugin", package: "swift-syntax"), "MacroSupport"]'
        expected_label = '"//Sources/MacroSupport",'

        result = run(sys.executable, "scripts/modules.py", cwd=directory)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(expected_manifest, (directory / "Package.swift").read_text())
        self.assertIn(expected_label, (directory / "Sources" / "GreetingsMacros" / "BUILD.bazel").read_text())

    def test_check_refuses_a_plugin_on_a_plugin_an_ios_or_testing_module_one_reaching_a_plugin_or_an_example(self):
        directory = self.render(self.scratch / "plugin-refusals", "--library", "--ios")
        modules = directory / "scripts" / "modules.py"
        package = '    ("swift-syntax", "https://github.com/swiftlang/swift-syntax", "range:603.0.0..<605.0.0"),\n'
        original = (modules.read_text()
                    .replace("PACKAGES = [\n", "PACKAGES = [\n" + package, 1)
                    .replace("MODULES = [\n", 'MODULES = [\n    ("Support", "Macros", "Expansions.", []),\n'
                             '    ("Declarations", "Macros", "Declares #demo.", ["DemoMacros"]),\n', 1))
        demo = '("DemoMacros", "Macros", "Expands #demo.", ["swift-syntax/SwiftCompilerPlugin"])'

        def generate(dependency, **tables):
            text = original.replace("MACROS = []", f'MACROS = [{demo}, ("OtherMacros", "Macros", "Expands #other.", ["{dependency}"])]', 1)
            for table, value in tables.items():
                text = re.sub(rf"^{table} = \[\](  # [!a-z]+:line)?$", f"{table} = {value}", text, count=1, flags=re.M)
            modules.write_text(text)
            return run(sys.executable, "scripts/modules.py", cwd=directory)

        actual = {
            "plugin": generate("DemoMacros").stderr,
            "ios": generate("Support", IOS_MODULES='["Support"]').stderr,
            "testing": generate("Support", TESTING_MODULES='["Support"]', NON_UMBRELLA_MODULES='["Support"]').stderr,
            "reaches": generate("Declarations").stderr,
            "example": generate("Support", EXAMPLE_MODULES='["Support"]').stderr,
        }
        listed = generate("Support", EXAMPLE_MODULES='["Support", "OtherMacros"]')

        self.assertIn("the plugin OtherMacros depends on the plugin DemoMacros: share the code through a module in MODULES", actual["plugin"])
        self.assertIn("the plugin OtherMacros depends on the iOS module Support, which the compiler can't load", actual["ios"])
        self.assertIn("the plugin OtherMacros depends on Support, which imports Testing, a test-only library", actual["testing"])
        self.assertIn("the plugin OtherMacros depends on Declarations, which reaches the plugin DemoMacros", actual["reaches"])
        self.assertIn("the plugin OtherMacros depends on the example module Support, so it must be in EXAMPLE_MODULES", actual["example"])
        self.assertEqual(listed.returncode, 0, listed.stderr)

    def test_update_reports_a_table_the_project_already_defines_and_never_leaves_the_empty_one_in_effect(self):
        # The template before it had MACROS: the stock file without its assignment.
        modules = self.template / "scripts" / "modules.py"
        stock = modules.read_text()
        git("checkout", "-q", "-b", "before-macros", cwd=self.template)
        modules.write_text(stock.replace("MACROS = []\n", "", 1))
        git("commit", "-q", "-am", "before MACROS", cwd=self.template)
        before = git("rev-parse", "HEAD", cwd=self.template)
        result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", "--library", NAME,
                     str(self.scratch / "own-macros"), cwd=self.scratch)
        git("checkout", "-q", "main", cwd=self.template)
        self.assertEqual(result.returncode, 0, result.stderr)
        # A project that defined the table itself, far from where the template later puts it.
        project = self.scratch / "own-macros"
        (project / ".template.json").write_text(json.dumps({"commit": before, "name": NAME, "type": "library"}) + "\n")
        own_row = 'MACROS = [("DemoMacrosPlugin", "Macros", "Expands #demo.", [])]\n'
        project_modules = project / "scripts" / "modules.py"
        text = project_modules.read_text()
        project_modules.write_text(text.replace("\ndef main():", f"\n{own_row}\n\ndef main():", 1))
        git("init", "-q", "-b", "main", cwd=project)
        git("add", "-A", cwd=project)
        git("commit", "-q", "-m", "project", cwd=project)
        generated = (project / "tools" / "macros.bzl").read_bytes()

        result = self.template_py("update", str(project), "--to", self.commit)

        self.assertNotEqual(result.returncode, 0, result.stdout)
        conflicts = result.stdout.split("CONFLICTS:", 1)[-1].split("\n\n", 1)[0]
        self.assertIn("scripts/modules.py (a table or function is defined twice", conflicts)
        self.assertIn(own_row, project_modules.read_text())
        actual = run(sys.executable, "scripts/modules.py", cwd=project)
        self.assertNotEqual(actual.returncode, 0)
        self.assertIn("defines MACROS more than once", actual.stderr)
        self.assertEqual((project / "tools" / "macros.bzl").read_bytes(), generated)

    def test_bootstrap_leaves_out_what_git_ignores_in_the_template_and_keeps_untracked_files(self):
        # Another tool's state, ignored only by this checkout's own exclude file: a nested template
        # copy whose BUILD.bazel files would become packages of the project.
        exclude = self.template / ".git" / "info" / "exclude"
        stock_exclude = exclude.read_text()
        exclude.write_text(stock_exclude + ".delta/\n")
        nested = self.template / ".delta" / "worktrees" / "f5" / "ProjectTemplate" / "Benchmarks"
        nested.mkdir(parents=True)
        (nested / "BUILD.bazel").write_text('load("//tools:benchmarks.bzl", "benchmarks")\n')
        untracked = self.template / "Untracked.md"
        untracked.write_text("Not yet added.\n")
        # The checkout this copy came from may hold a board already.
        board = self.template / ".kanban" / "template-test-board.json"
        board.parent.mkdir(exist_ok=True)
        board.write_text("{}\n")

        def restore():
            exclude.write_text(stock_exclude)
            shutil.rmtree(self.template / ".delta")
            untracked.unlink()
            board.unlink()
        self.addCleanup(restore)
        directory = self.scratch / "ignored-library"

        result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", "--library", NAME,
                     str(directory), cwd=self.scratch)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((directory / ".delta").exists())
        self.assertEqual((directory / "Untracked.md").read_text(), "Not yet added.\n")
        for left_out in ("bootstrap.sh", "template.py", "template_test.py", "templates", "ci-image", ".kanban"):
            self.assertFalse((directory / left_out).exists(), left_out)

    def test_bootstrap_leaves_out_what_git_ignores_in_a_type_directory(self):
        exclude = self.template / ".git" / "info" / "exclude"
        stock_exclude = exclude.read_text()
        exclude.write_text(stock_exclude + ".delta/\n")
        nested = self.template / "templates" / "server" / ".delta" / "clone"
        nested.mkdir(parents=True)
        (nested / "BUILD.bazel").write_text("\n")

        def restore():
            exclude.write_text(stock_exclude)
            shutil.rmtree(self.template / "templates" / "server" / ".delta")
        self.addCleanup(restore)
        directory = self.scratch / "ignored-server"

        result = run("bash", str(self.template / "bootstrap.sh"), "--render-only", "--server", "--ci", NAME,
                     str(directory), cwd=self.scratch)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((directory / ".delta").exists())
        self.assertTrue((directory / "Sources" / "App" / "Routes.swift").is_file())


if __name__ == "__main__":
    unittest.main()
