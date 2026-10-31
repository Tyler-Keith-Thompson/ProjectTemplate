#!/usr/bin/env python3
"""Differential testing: the library against reference implementations on the same random cases.

    python3 scripts/differential.py                    # 2,000 cases, a random seed, every area
    python3 scripts/differential.py --cases 500 --seed 7
    python3 scripts/differential.py --module Greetings # only that module's comparisons

Each area is a file scripts/differential_<area>.py naming the library MODULE it checks and
defining generate(rng) (one case), reference(case) (the reference's answer) and
compare(case, mine, ref) (a list of problems, empty when they agree). The library side is
Differential/, an executable that reads a batch of cases as JSON and answers each area it is
asked for (Differential/Sources/<Project>Differential/<Area>.swift).

Every case holds every area's input, generated from one seeded generator in a fixed order, so a
seed gives the same cases whatever --module chooses; only the other areas' library calls and
comparisons are skipped.

The library side is built through Bazel (//Differential:<Project>Differential, optimized, in the
output base `just test-release` uses), or through SwiftPM with --swiftpm. The references run
under `uv` with the versions pinned in REFERENCES (the script re-executes itself through
`uv run`), so nothing is installed globally. A failing case is written to Differential/Failures/
as JSON, with its seed; the case becomes a regression test, then the file goes.
"""

import argparse
import glob
import importlib
import json
import os
import random
import runpy
import subprocess
import sys

# The reference packages, pinned. Add one here when an area imports it.
REFERENCES = ["regex==2024.11.6"]

if not os.environ.get("DIFFERENTIAL_UV"):
    os.environ["DIFFERENTIAL_UV"] = "1"
    command = ["uv", "run", "--quiet", "--no-project"] + [a for r in REFERENCES for a in ("--with", r)]
    try:
        os.execvp("uv", command + ["python3", *sys.argv])
    except FileNotFoundError:
        sys.exit("just diff runs its references through uv: brew install uv")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = runpy.run_path(os.path.join(ROOT, "scripts", "modules.py"))["PROJECT"]
PACKAGE = os.path.join(ROOT, "Differential")
FAILURES = os.path.join(PACKAGE, "Failures")
EXECUTABLE = f"{PROJECT}Differential"
BAZEL_TARGET = f"//Differential:{EXECUTABLE}"
# The justfile's BAZEL_RELEASE: optimized builds keep their own output base.
BAZEL_RELEASE = ["bazel", f"--output_base={os.path.expanduser('~/Library/Caches')}/bazel-{PROJECT.lower()}-release"]
SWIFT = ["env", "-u", "TOOLCHAINS", "xcrun", "--toolchain", "default", "swift"]

# Cases per library process. Every run is bounded, so a library bug that never terminates fails
# the run rather than hanging it; a crashed or hung batch is rerun a case at a time to find the
# culprits, stopping after a few.
BATCH = 500
BATCH_TIMEOUT = 300
CASE_TIMEOUT = 10
MAX_ISOLATED = 5


def areas():
    """Every scripts/differential_<area>.py, by its section name."""
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    paths = sorted(glob.glob(os.path.join(ROOT, "scripts", "differential_*.py")))
    return {os.path.basename(p)[len("differential_"):-3]: importlib.import_module(os.path.basename(p)[:-3]) for p in paths}


def build_library(swiftpm):
    """Builds the library side optimized and returns the executable's path."""
    if swiftpm:
        build = subprocess.run(SWIFT + ["build", "-c", "release"], cwd=PACKAGE, capture_output=True, text=True, timeout=1800)
        if build.returncode != 0:
            sys.exit("The differential build failed:\n" + build.stdout[-3000:] + build.stderr[-3000:])
        return os.path.join(PACKAGE, ".build", "release", EXECUTABLE)
    # The workspace's bazel-bin and bazel-out links stay on the debug output base.
    flags = ["--config=release", "--experimental_convenience_symlinks=ignore"]
    build = subprocess.run(BAZEL_RELEASE + ["build", *flags, BAZEL_TARGET], cwd=ROOT, capture_output=True, text=True, timeout=1800)
    if build.returncode != 0:
        sys.exit("The differential build failed:\n" + build.stderr[-6000:])
    where = subprocess.run(BAZEL_RELEASE + ["cquery", *flags, "--output=files", BAZEL_TARGET], cwd=ROOT,
                           capture_output=True, text=True, timeout=600)
    root = subprocess.run(BAZEL_RELEASE + ["info", *flags, "execution_root"], cwd=ROOT, capture_output=True, text=True, timeout=600)
    if where.returncode != 0 or root.returncode != 0 or not where.stdout.strip():
        sys.exit("Could not find the differential executable:\n" + where.stderr[-3000:] + root.stderr[-3000:])
    return os.path.join(root.stdout.strip(), where.stdout.split()[0])


def record(case, problems, seed):
    os.makedirs(FAILURES, exist_ok=True)
    name = f"seed{seed}-{len(os.listdir(FAILURES)):04}.json"
    with open(os.path.join(FAILURES, name), "w") as f:
        json.dump({"seed": seed, "problems": problems, "case": case}, f, indent=1, ensure_ascii=False)
    if len(os.listdir(FAILURES)) <= 5:
        print(f"{name}: " + "; ".join(problems)[:600])


def main():
    known = areas()
    by_module = {known[a].MODULE.lower().removesuffix("module"): a for a in known}
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, help="default: a random one, printed")
    parser.add_argument("--module", action="append", default=[],
                        help=f"a library module to compare (repeatable): {', '.join(sorted(known[a].MODULE for a in known))}")
    parser.add_argument("--swiftpm", action="store_true", help="build the library side with SwiftPM instead of Bazel")
    args = parser.parse_args()

    chosen = []
    for module in args.module:
        area = by_module.get(module.lower().removesuffix("module"))
        if area is None:
            sys.exit(f"No differential area for {module}; there are {', '.join(sorted(known[a].MODULE for a in known))}")
        chosen.append(area)
    sections = chosen or sorted(known)
    seed = args.seed if args.seed is not None else random.randrange(1 << 31)
    rng = random.Random(seed)
    cases = [{area: known[area].generate(rng) for area in sorted(known)} for _ in range(args.cases)]

    command = [build_library(args.swiftpm), *sections]
    failures = 0
    for start in range(0, len(cases), BATCH):
        batch = cases[start:start + BATCH]
        try:
            run = subprocess.run(command, input=json.dumps(batch), capture_output=True, text=True, timeout=BATCH_TIMEOUT)
            crashed = run.returncode != 0
        except subprocess.TimeoutExpired:
            crashed = True
        if crashed:
            found = 0
            for case in batch:
                if found >= MAX_ISOLATED:
                    break
                try:
                    one = subprocess.run(command, input=json.dumps([case]), capture_output=True, text=True, timeout=CASE_TIMEOUT)
                    problem = f"the library crashed: {one.stderr.strip()[-500:]}" if one.returncode != 0 else None
                except subprocess.TimeoutExpired:
                    problem = f"the library did not finish within {CASE_TIMEOUT} s"
                if problem:
                    failures += 1
                    found += 1
                    record(case, [problem], seed)
            continue
        for case, mine in zip(batch, json.loads(run.stdout)):
            problems = [f"{area}: {problem}" for area in sections
                        for problem in known[area].compare(case[area], mine.get(area), known[area].reference(case[area]))]
            if problems:
                failures += 1
                record(case, problems, seed)
    only = "" if sections == sorted(known) else f", {', '.join(sections)} only"
    print(f"{args.cases} cases (seed {seed}{only}): "
          + (f"{failures} disagreement(s) in {os.path.relpath(FAILURES, ROOT)}/" if failures else "all agree"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
