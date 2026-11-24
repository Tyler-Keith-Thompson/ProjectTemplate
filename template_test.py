#!/usr/bin/env python3
"""Tests of template.py's add and remove, against a copy of this checkout committed in a scratch repository.

    python3 template_test.py

Each test makes a project the way bootstrap.sh would (a render, its generated files, a stamp, one
commit), changes it the way an owner might, runs template.py from the copy, and compares the result
with a fresh render. The copy includes uncommitted changes, so the tests check the working tree.
Like template.py, this file stays behind: bootstrap.sh leaves it out of projects.
"""
import json
import pathlib
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
                 "examples": False, "fly": False, "database": False, "ci": True, "trunk": False, **stamp}
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
            self.assertIn("./template.py add <project> --ios", result.stderr)

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
