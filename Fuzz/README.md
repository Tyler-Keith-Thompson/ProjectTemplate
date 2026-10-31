# Fuzzing

Coverage-guided fuzz targets for [libFuzzer](https://llvm.org/docs/LibFuzzer.html), one per
module, in their own package so the library never links the fuzzer runtime.

| Target | Checks against |
|---|---|
| `FuzzGreetings` | Names from a small alphabet (combining accents, an emoji) and sequences of modifiers: the text written out from the name, register and punctuation after every modifier; an earlier copy unchanged; the checked initializer throwing exactly for an empty name; equality and hashing with a greeting rebuilt from the model |

Each target reads its input as a sequence of small choices (`FuzzInput`): an operation and its
arguments. Every byte string decodes, and a mutation of one byte changes one choice, so libFuzzer
explores operation sequences rather than parse errors.

## Running

| Command | Does |
|---|---|
| `just fuzz` | Every target for 60 s, all at once, splitting the cores between them |
| `just fuzz FuzzGreetings -t 600 -j 16` | One target for 10 minutes on 16 workers |
| `just fuzz-regress` | Replays every corpus once (seconds); run after changing a fuzzed module |
| `just fuzz-repro <target> <crash file>` | Replays a crash and writes a minimized copy beside it |

A run is bounded by wall time. New inputs that add coverage are merged into `Fuzz/Corpus/<target>/`
(local, not committed), so the next run resumes from there. Crashes are written to
`Fuzz/Crashes/<target>/`; each one becomes a test in the module's suite, and then the file is
deleted.

## Toolchain

Xcode's toolchain does not include the libFuzzer runtime (`libclang_rt.fuzzer_osx.a`); the
swift.org toolchains do. The scripts build with `swiftly run swift build +6.3.3` (override with
`<PROJECT>_FUZZ_SWIFT`, the project's name in capitals), so install it once with
`swiftly install 6.3.3`. The build may print `unknown argument: '-target-arch-variant'` while
reading a newer SDK's interfaces, then falls back and succeeds; the scripts hide it.

Targets are built in release mode with AddressSanitizer: preconditions stay on, and unsafe buffer
code is checked for out-of-bounds access.

SwiftPM links each executable against its own `main`, which conflicts with libFuzzer's, so each
target has an `@main` that calls `runFuzzer`, which starts libFuzzer through
`LLVMFuzzerRunDriver`.

## Adding a target

Add a directory `Sources/Fuzz<Module>/` with an `@main` enum calling `runFuzzer`, a line in
`Package.swift` naming the modules it imports (their SwiftPM products), and a row in the table
above. Check against a model simple enough to be obviously right, check after every operation,
keep values small so collisions and ties are common, and include a snapshot copy to catch
copy-on-write bugs.
