"""Tests of tools/docc_symbol_graph.py: relocated source info, relocated symbol graphs, the guard."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

RUNFILES = os.getcwd()
TOOL = os.path.join(RUNFILES, "tools", "docc_symbol_graph.py")

specification = importlib.util.spec_from_file_location("docc_symbol_graph", TOOL)
docc_symbol_graph = importlib.util.module_from_spec(specification)
specification.loader.exec_module(docc_symbol_graph)


class SourceInfoTests(unittest.TestCase):
    def test_each_sources_prefix_becomes_a_relative_one_of_the_same_length(self):
        data = (
            b"\x04\x00\x00\x00/gone/output/execroot/_main/Sources/A/A.swift\x00"
            b"/gone/output/execroot/_main/Sources/A/Other.swift\x00\x22\x0e"
        )

        actual, count = docc_symbol_graph.relocate_source_info(
            data, ["Sources/A/A.swift", "Sources/A/Other.swift"]
        )

        expected_prefix = b"./" * 14
        self.assertEqual(count, 2)
        self.assertEqual(len(actual), len(data))
        self.assertEqual(
            actual,
            b"\x04\x00\x00\x00" + expected_prefix + b"Sources/A/A.swift\x00"
            + expected_prefix + b"Sources/A/Other.swift\x00\x22\x0e",
        )

    def test_an_odd_length_prefix_ends_in_a_doubled_slash(self):
        data = b"\x00/odd1/execroot/_main/Sources/A/A.swift\x00"

        actual, count = docc_symbol_graph.relocate_source_info(data, ["Sources/A/A.swift"])

        expected = b"\x00" + b"./" * 9 + b".//" + b"Sources/A/A.swift\x00"
        self.assertEqual(count, 1)
        self.assertEqual(actual, expected)

    def test_a_path_from_any_root_is_relocated_not_only_an_execution_root(self):
        data = b"\x00/b/f/ws/Sources/A/A.swift\x00"

        actual, count = docc_symbol_graph.relocate_source_info(data, ["Sources/A/A.swift"])

        expected = b"\x00././././Sources/A/A.swift\x00"
        self.assertEqual(count, 1)
        self.assertEqual(actual, expected)

    def test_a_path_that_only_ends_like_a_source_is_left_alone(self):
        data = b"\x00/root/Sources/A/NotA.swift\x00/root/Sources/A/A.swift.orig\x00"

        actual, count = docc_symbol_graph.relocate_source_info(data, ["Sources/A/A.swift"])

        self.assertEqual(count, 0)
        self.assertEqual(actual, data)

    def test_no_sources_leave_the_data_unchanged(self):
        data = b"\x00/root/execroot/_main/Sources/A/A.swift\x00"

        actual, count = docc_symbol_graph.relocate_source_info(data, [])

        self.assertEqual(count, 0)
        self.assertEqual(actual, data)

    def test_no_relative_prefix_is_one_byte_long(self):
        with self.assertRaises(ValueError):
            docc_symbol_graph.relative_prefix(1)


class RelocationTests(unittest.TestCase):
    def test_a_relative_uri_is_rooted_at_the_checkout(self):
        text = '{"uri":"file://./././/Sources/A/A.swift"}'

        actual = docc_symbol_graph.relocated(text, "/checkout")

        expected = '{"uri":"file:///checkout/Sources/A/A.swift"}'
        self.assertEqual(actual, expected)

    def test_an_execution_root_uri_is_rooted_at_the_checkout(self):
        text = '{"uri":"file:///var/out/execroot/_main/Sources/A/A.swift"}'

        actual = docc_symbol_graph.relocated(text, "/checkout")

        expected = '{"uri":"file:///checkout/Sources/A/A.swift"}'
        self.assertEqual(actual, expected)

    def test_another_absolute_uri_is_left_alone(self):
        text = '{"uri":"file:///usr/include/stdio.h"}'

        actual = docc_symbol_graph.relocated(text, "/checkout")

        self.assertEqual(actual, text)

    def test_doc_comment_uris_are_relocated_as_well_as_symbol_locations(self):
        text = (
            '{"docComment":{"uri":"file://././Sources/A/A.swift"},'
            '"location":{"uri":"file://././Sources/A/A.swift"}}'
        )

        actual = docc_symbol_graph.relocated(text, "/checkout")

        expected = (
            '{"docComment":{"uri":"file:///checkout/Sources/A/A.swift"},'
            '"location":{"uri":"file:///checkout/Sources/A/A.swift"}}'
        )
        self.assertEqual(actual, expected)


class GuardTests(unittest.TestCase):
    def test_a_documented_symbol_without_a_location_is_reported(self):
        graph = {"symbols": [
            {"identifier": {"precise": "s:1A5ThingV"}, "docComment": {"lines": []}},
        ]}

        actual = docc_symbol_graph.documented_without_location(graph, "A")

        self.assertEqual(actual, ["s:1A5ThingV"])

    def test_a_documented_symbol_with_a_location_is_not_reported(self):
        graph = {"symbols": [
            {
                "identifier": {"precise": "s:1A5ThingV"},
                "docComment": {"lines": []},
                "location": {"uri": "file:///checkout/Sources/A/A.swift"},
            },
        ]}

        actual = docc_symbol_graph.documented_without_location(graph, "A")

        self.assertEqual(actual, [])

    def test_an_undocumented_symbol_without_a_location_is_not_reported(self):
        graph = {"symbols": [{"identifier": {"precise": "s:1A5ThingV"}}]}

        actual = docc_symbol_graph.documented_without_location(graph, "A")

        self.assertEqual(actual, [])

    def test_a_synthesized_member_is_not_reported(self):
        graph = {"symbols": [
            {
                "identifier": {"precise": "s:SQsE2neoiySbx_xtFZ::SYNTHESIZED::s:1A5ThingV"},
                "docComment": {"lines": []},
            },
        ]}

        actual = docc_symbol_graph.documented_without_location(graph, "A")

        self.assertEqual(actual, [])

    def test_a_doc_comment_inherited_from_another_module_is_not_reported(self):
        graph = {"symbols": [
            {"identifier": {"precise": "s:1A5ThingV4hashyys"}, "docComment": {"module": "Swift"}},
        ]}

        actual = docc_symbol_graph.documented_without_location(graph, "A")

        self.assertEqual(actual, [])


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        self.source = os.path.join(self.directory, "extracted")
        self.output = os.path.join(self.directory, "relocated")
        os.makedirs(self.source)
        os.makedirs(self.output)

    def tearDown(self):
        shutil.rmtree(self.directory, ignore_errors=True)

    def test_symbol_graph_fails_naming_the_symbols_without_a_location(self):
        graph = {"symbols": [{"identifier": {"precise": "s:1A5ThingV"}, "docComment": {}}]}
        with open(os.path.join(self.source, "A.symbols.json"), "w") as f:
            json.dump(graph, f)

        actual = subprocess.run(
            [sys.executable, TOOL, "symbol-graph", "A", "/checkout", self.source, self.output],
            capture_output=True,
            text=True,
        )

        self.assertEqual(actual.returncode, 1)
        self.assertIn("1 documented symbol(s) of A have no source location", actual.stderr)
        self.assertIn("s:1A5ThingV", actual.stderr)

    def test_symbol_graph_writes_every_graph_relocated(self):
        text = '{"symbols":[{"identifier":{"precise":"s:1A5ThingV"},"docComment":{},' \
            '"location":{"uri":"file://././Sources/A/A.swift"}}]}'
        for name in ["A.symbols.json", "A@Swift.symbols.json"]:
            with open(os.path.join(self.source, name), "w") as f:
                f.write(text)

        actual = subprocess.run(
            [sys.executable, TOOL, "symbol-graph", "A", "/checkout", self.source, self.output],
            capture_output=True,
            text=True,
        )

        expected = text.replace("file://././", "file:///checkout/")
        self.assertEqual(actual.returncode, 0, actual.stderr)
        self.assertEqual(sorted(os.listdir(self.output)), ["A.symbols.json", "A@Swift.symbols.json"])
        for name in os.listdir(self.output):
            with open(os.path.join(self.output, name)) as f:
                self.assertEqual(f.read(), expected)


if __name__ == "__main__":
    unittest.main()
