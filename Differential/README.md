# Differential testing

Runs the library and independent reference implementations on the same random cases and compares
the answers. The references are pinned in `scripts/differential.py` (`REFERENCES`) and run through
`uv`, so nothing is installed globally.

| Command | Does |
|---|---|
| `just diff` | 2,000 random cases with a random seed, every area |
| `just diff --cases 20000 --seed 7` | More cases, reproducibly |
| `just diff --module Greetings` | Only one module's comparisons; repeat the flag for several |
| `just diff --swiftpm` | Build the library side with SwiftPM instead of Bazel |

`ProjectNameDifferential` (this package) reads a batch of cases as JSON and answers them with the
library; `scripts/differential.py` generates the cases from a seed, asks each area's reference the
same questions, and compares. A disagreement is written to `Failures/` (not committed) with its
seed and the case; it becomes a regression test in the module's suite, then the file goes.

The executable is built through Bazel, `//Differential:ProjectNameDifferential` (a `manual`
`swift_binary`), with `--config=release` in the output base `just test-release` uses, so a run only
compiles what changed. `scripts/modules.py` writes its BUILD.bazel and Package.swift from one
list, `DIFFERENTIAL_DEPENDENCIES`. The SwiftPM package serves `--swiftpm`.

## Areas

| Area | Library | Reference |
|---|---|---|
| `greetings` | `Greeting(checkedName:)`, the modifiers in sequence, `text` and its `count` | The text written out in Python; extended grapheme clusters from the `regex` package (`\X`) for the character count, on names with combining accents, emoji sequences and flags |

## Adding an area

1. `scripts/differential_<area>.py`: `MODULE` (the library module it checks), `generate(rng)`
   (one case, a JSON value, drawn only from `rng`), `reference(case)` and
   `compare(case, mine, reference)` (a list of problems, empty when they agree). A reference
   package goes in `REFERENCES`, pinned.
2. `Sources/ProjectNameDifferential/<Area>.swift`: the case and answer types, and a field for
   each in `main.swift`'s `Case` and `Answer`, answered when `asked("<area>")`.
3. The module in `DIFFERENTIAL_DEPENDENCIES` (`scripts/modules.py`), then `just modules`.

Compare only what ties cannot change: where correct implementations may differ (an order among
equals, which of several valid answers), validate the library's answer instead of matching it.
