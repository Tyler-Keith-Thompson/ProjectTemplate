# ProjectName: notes for coding agents

<One paragraph: what ProjectName is, what it optimizes for, who uses it.> Swift 6.3 (minimum).
Bazel is the development build; SwiftPM is the published package. `README.md` is the user-facing
overview.

This file came from a project template. Sections marked *default* describe how the owner likes
every project built; delete a rule only when it cannot apply here, and say so in the commit.

## Layout

```
Sources/<Module>/                One directory per module, each with a generated BUILD.bazel
Sources/ProjectName/             Umbrella module (@_exported imports) and the landing DocC catalog
Tests/<Module>Tests/             One test target per module; Performance/ holds speed-reliant tests
Sources/App/                     The Vapor application: configure(_:), routes, models <!-- server:line -->
Sources/ProjectNameServer/       The executable (@main): builds an Application, configures, serves <!-- server:line -->
Tests/ProjectNameTests/          The README examples, verbatim <!-- library:line -->
Tests/ProjectNameTestSupport/    Shared test fixtures (data only)
scripts/modules.py               The module graph
scripts/mutants/<Module>.py      Planted bugs for `just mutate <Module>` (scripts/mutate.py) <!-- mutation:line -->
Fuzz/Sources/Fuzz<Module>/       A libFuzzer target per module, in the separate Fuzz/ package <!-- fuzz:line -->
Differential/                    The library side of `just diff`; scripts/differential_<area>.py the references <!-- differential:line -->
Explore/                         The browser explorer: pages running the library as WebAssembly (`just explore`) <!-- explore:line -->
tools/                           Bazel rule wrappers (warnings as errors, Swift 6 mode), DocC rules;
                                 tools/bazel turns BuildBuddy on when the Keychain holds its key
Dockerfile                       The production image, built with SwiftPM <!-- server:line -->
LoadTests/load.js                The k6 load test that `just load` runs against the image <!-- server:line -->
fly.toml                         The Fly.io app <!-- fly:line -->
litestream.yml                   SQLite replication to B2; scripts/docker-entrypoint.sh runs it <!-- litestream:line -->
```

<!-- benchmarks:begin -->
`Benchmarks/` is a separate SwiftPM package (ordo-one/benchmark) that Bazel ignores; see
`Benchmarks/README.md`.
<!-- benchmarks:end -->
<!-- fuzz:begin -->
`Fuzz/` is a separate SwiftPM package of libFuzzer targets that Bazel ignores, built with a
swift.org toolchain through swiftly (`swiftly install 6.3.3`); see `Fuzz/README.md`.
<!-- fuzz:end -->

### Module graph

`scripts/modules.py` is the source of truth for modules, their dependencies, test targets,
external packages and platforms. `just modules` regenerates `Package.swift`, every `BUILD.bazel`,
the umbrella module and `swift/Package.swift` from it. Never edit the generated files by hand;
`//:package_swift_test` fails when `Package.swift` disagrees with the Bazel graph.

- Add a module: a row in `MODULES` (name, group, description, dependencies), then `just modules`.
- Add a test target: a row in `TEST_TARGETS`. A target with a `Performance/` directory of Swift
  sources must be listed in `PERFORMANCE_TESTS`, and the reverse.
- Add an executable: a row in `EXECUTABLES` (name, description, dependencies). It holds only
  `@main`; its code lives in a module, where tests reach it.
- Add an external package: a row in `PACKAGES`, its `swiftpkg_<identity>` repository in
  `MODULE.bazel`'s `use_repo`, then `just modules` and `just resolve`.
- Generate mocks: uncomment the Mockable row in `PACKAGES`, add `mockable/Mockable` to the
  module that declares the protocol and to its test target, add `swiftpkg_mockable` to
  `use_repo`, then `just modules` and `just resolve`. The generator defines `MOCKING` for that
  module in debug builds only, in both build systems.
- A module name takes a `Module` suffix only when it would otherwise equal its main type's name
  (`GreetingModule` would hold `Greeting`). No catch-all modules ("Core", "Utilities").

## Commands

Every shell command gets a timeout. macOS has no `timeout`; use
`perl -e 'alarm 1800; exec @ARGV' <command>`. A bug can make a loop run forever.

| Command | Does |
|---|---|
| `just build` / `just test` | Build / test everything (debug) |
| `bazel test //Tests/XTests` | One test target (`just test-one //Tests/XTests`) |
| `just filter <pattern>` | Tests whose name matches |
| `just mutate <Module> [--all]` | Mutation testing: every planted bug in `scripts/mutants/<Module>.py` must be caught <!-- mutation:line --> |
| `just fuzz [Fuzz<Module>] [-t secs]` | libFuzzer, time-boxed (60 s per target); `just fuzz-regress` replays the corpus, `just fuzz-repro <target> <file>` a crash <!-- fuzz:line --> |
| `just diff [--module X] [--cases N] [--seed S]` | Differential tests against pinned reference implementations (through `uv`) <!-- differential:line --> |
| `just wasi-test [-c release] [--targets X,Y]` | SwiftPM tests on wasm32-wasi under wasmtime: a 32-bit `Int` <!-- wasm:line --> |
| `just explore` | Build the browser explorer into `Explore/dist` (serve it to try a page); the DocC workflow publishes it at `<pages>/explore/` <!-- explore:line --><!-- ci:line --> |
| `just explore` | Build the browser explorer into `Explore/dist`; serve it to try a page <!-- explore:line --><!-- !ci:line --> |
| `just test-release` | `--config=release`: builds and runs only the `XPerformanceTests` targets |
| `just spm-test`, `just verify` | SwiftPM tests; both build systems |
| `just modules` | Regenerate build files from `scripts/modules.py` |
| `just resolve` | Re-resolve Bazel's SwiftPM dependencies after editing `PACKAGES` |
| `just bench [--target X]` | Benchmarks; `just bench-compare` against the `main` baseline <!-- benchmarks:line --> |
| `just bench-simulated-compare [--target X]` | Simulated counts (Callgrind in a Linux VM, from `~/workspace/BenchmarkHarness`) against the committed `simulated` baseline; `just bench-simulated [--target X]` re-records it <!-- benchmarks:line --> |
| `just docs` | Combined DocC site into `.build/docs` |
| `just generate` | Xcode project from the Bazel graph |
| `just buildbuddy-key`, `just ci-secrets` | Store the BuildBuddy key in the Keychain (once per Mac; builds then use the remote cache); set it as this repository's Actions secret with `gh` <!-- ci:line --> |
| `just buildbuddy-key` | Store the BuildBuddy key in the Keychain (once per Mac; builds then use the remote cache) <!-- !ci:line --> |
| `just template-update` | Merge the project template's changes since `.template.json`'s commit; resolve conflicts, then `just modules`, `just test` |
| `just run [args]` | The server on port 8080 (`bazel run //Sources/ProjectNameServer -- serve`) <!-- server:line --> |
| `just docker` | Build the production image and run it on port 8080 <!-- server:line --> |
| `just load [k6 args]` | Load-test a fresh production image with k6; `BASE_URL=… just load` for a running server <!-- server:line --> |
| `just deploy` | Deploy this checkout to Fly.io <!-- fly:line --> |
| `bazel query 'rdeps(//Tests/..., //Sources/X)'` | Test targets affected by a change to X |

- Debug is the default configuration. Every test target except the `XPerformanceTests` ones is
  tagged `debug-only`, which `--config=release` filters out.
- A test that bounds wall-clock time, or runs a large input under `.timeLimit`, belongs in
  `Tests/X/Performance/`.
- Release builds use their own output base (see the justfile). Don't create other output bases
  or copies of the repo, and shut down any extra Bazel server you start.
- Run suites through Bazel, not `swift test --filter`.
- First-party warnings are errors (`tools/swift_rules.bzl`); dependencies build quietly. Fix the
  warning, never suppress it.
- Exit tests (`#expect(processExitsWith:)`) go in files of their own, apart from the other tests:
  builds for platforms that cannot start a child process leave those files out.
<!-- wasm:begin -->

### 32-bit `Int` (WebAssembly)

watchOS's arm64_32 and wasm32 have a 32-bit `Int`. `just wasi-test` (`scripts/wasi_test.py`)
builds the SwiftPM test targets with `swift build --build-tests --swift-sdk
swift-6.3.3-RELEASE_wasm` through swiftly into `.build/wasm`, then runs each binary with
`wasmtime run --dir . <binary> --testing-library swift-testing`, logs in `.build/wasm/logs`.
Needs swiftly's 6.3.3 toolchain, its WebAssembly SDK (`swift sdk list`; swift.org's "Getting
Started with Swift SDKs for WebAssembly" has the install command) and `brew install wasmtime`. If
the toolchain crashes on the manifest against a newer Xcode's SDK, pass `--xcode
/Applications/Xcode-<older>.app`.

- One binary of every target can pass wasmtime's limit of a million functions, so targets run in
  groups (`<PROJECT>_WASI_TESTS`, the project's name in capitals, makes `Package.swift` declare
  only those).
- Not run on WASI: files with exit tests (no child processes; the manifest leaves them out), and
  anything needing threads (`#if !os(WASI)`). On WASI a time limit's timer holds the thread until
  it expires, after the body has run, so every `.timeLimit` test reports its limit exceeded; the
  script reports the issues besides those.
<!-- wasm:end -->

<!-- server:begin -->
## Server

`App` is a library so tests can reach it; the executable only calls `configure(_:)` and serves.

- Routes live in `Sources/App/Routes.swift`, registered from `configure(_:)`. Tests use
  VaporTesting: `withApp(configure: configure) { app in try await app.testing().test(...) }`, so
  each test runs the production configuration on an application of its own, without a port.
- Configuration comes from the environment (`Environment.get`), never from files baked into the
  image. Production refuses to start when something it needs is missing rather than fall back.
<!-- database:begin -->
- The database is SQLite through Fluent: the file at `DATABASE_PATH`, else memory, which each
  test's application gets a fresh one of. Add a migration for every schema change, after the
  existing ones in `configure(_:)`; never edit one that has shipped. Fluent models are classes
  (`final class …: Model, @unchecked Sendable`), the one exception to the value-type rule; keep
  them internal to `App`.
<!-- database:end -->
- The Docker image builds with SwiftPM from `Package.swift`, pinned by `swift/Package.resolved`
  (the same pins Bazel uses), so `just spm` must build too.
- `LoadTests/load.js` calls every route; add a request and a `check` there with each new route.
  Its thresholds (error rate, p95 and p99 latency) are the pass mark, and `just load` exits
  non-zero when one fails. Run it after a change to a hot route or to the image.
<!-- database:begin -->
  It starts the image on a throwaway database. Point `BASE_URL` at a deployed server only on
  purpose: the test writes greetings to whatever database it reaches.
<!-- database:end -->
<!-- fly:begin -->
- Every push to `main` deploys to Fly.io once CI passes (`deploy` in `Release.yml`). Run <!-- ci:line -->
  `just docker` before pushing a change to the image, its entry point or `fly.toml`. <!-- ci:line -->
- `just deploy` deploys this checkout to Fly.io; nothing deploys on push. Run `just docker` <!-- !ci:line -->
  before deploying a change to the image, its entry point or `fly.toml`. <!-- !ci:line -->
<!-- database:begin -->
- SQLite lives on one machine's volume, so the app runs on one machine (`--ha=false`). Don't
  scale it out.
<!-- database:end -->
<!-- litestream:begin -->
- Litestream (`litestream.yml`) replicates every write to B2 and the entry point restores the
  database on an empty volume. The replica is the backup: a migration that drops data drops it
  there too.
<!-- litestream:end -->
<!-- fly:end -->

<!-- server:end -->
## Building blocks

The owner's own libraries, first in line under "Don't reinvent the wheel" (House rules). Reach
for them before writing a graph, a container or an operator chain by hand, and before adding a
third-party package for the same job. Add one as a row in `PACKAGES` (`scripts/modules.py`).

| Library | What it is | Use it for |
|---|---|---|
| [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) | A generic, high-performance graph library: copy-on-write representations (`AdjacencyList`, `CompressedSparseRow`, `AdjacencyMatrix`, pseudographs, stable graphs), graph classes with invariants (`DirectedAcyclicGraph`, `BipartiteGraph`, `Tree`) and algorithms (traversal, shortest paths, flows, matching, connectivity, isomorphism, layout) | Anything shaped like a graph or DAG: dependency orderings, scheduling, routing, state machines, reachability. Products are per module (`.product(name: "ShortestPaths", package: "Grafluent")`); the umbrella is `Grafluent`. |
| [GrafluentCollections](https://github.com/Tyler-Keith-Thompson/GrafluentCollections) | Graph-shaped collections as copy-on-write values with the standard library's and swift-collections' API shape: balanced search trees (`AVLTree`/`AVLDictionary`, `RedBlackTree`, `Treap`, `SplayTree`) and `FenwickTree` so far; tries, suffix structures, decision diagrams, B-trees, segment, interval and spatial trees, ropes, persistent trees and an LRU cache planned. Tree- and graph-shaped ones convert to the matching Grafluent type | Sorted sets and dictionaries that take inserts and removals, prefix and range sums with updates; check its backlog before hand-writing a planned structure. Products are per module (`.product(name: "BinarySearchTrees", package: "GrafluentCollections")`); the umbrella is `GrafluentCollections`. |
| [DependencyInjection](https://github.com/Tyler-Keith-Thompson/DependencyInjection) | Swift 6 dependency injection: `Factory` values on `Container`, `@Injected` / `@LazyInjected` / `@ConstructorInjected`, unique, cached and shared scopes, hierarchical containers, and `withTestContainer` so concurrent tests never share state | Any seam a test needs to replace (clocks, network, storage). Tests wrap their body in `withTestContainer { }` and register doubles there. Product `DependencyInjection`. |
| [Afluent](https://github.com/Tyler-Keith-Thompson/Afluent) | Reactive operators over async/await: `DeferredTask` (a unit of work that yields one value) and `AsyncSequence` extensions with Combine's names (`map`, `flatMap`, `catch`, `retry`, `debounce`, `share`, …), plus `AfluentTesting` | Pipelines over async work where Combine would once have been used; a Combine replacement in new code. Products `Afluent` and, for test targets, `AfluentTesting`. |

Their conventions carry over: value types, typed errors, `checked:` spellings that throw where
the plain spelling traps, tests with Swift Testing.

## Workflow

### Adding a feature

A feature is done when it has all of these. Copy what its sibling features in the module already
have.

1. **Code and docs.** The implementation, with doc comments per "Docs" below. A new module gets a
   row in `scripts/modules.py`, then `just modules`, the README's module table and the umbrella
   DocC catalog's topic list.
2. **Tests** in `Tests/<Module>Tests`:
   - hand-worked cases;
   - edge cases: empty input, one element, the boundaries of every range;
   - `checked:` spellings and their errors;
   - exit tests for every trap;
   - a property test against a naive reference (`swift-property-based`).
<!-- mutation:begin -->
   - planted bugs in `scripts/mutants/<Module>.py` for the new code, then `just mutate <Module>`:
     every mutant caught, or a note in the spec on why a survivor is equivalent. A new module
     gets a spec of its own, copied from `Greetings.py`.
<!-- mutation:end -->
<!-- fuzz:begin -->
   - a fuzz target in `Fuzz/Sources/Fuzz<Module>` checking the new code against a model after
     every operation (see `Fuzz/README.md`), then `just fuzz Fuzz<Module>`. A crash becomes a
     test in the module's suite, then its file is deleted.
<!-- fuzz:end -->
<!-- differential:begin -->
   - a differential area where an independent implementation answers the same question
     (`Differential/README.md`, "Adding an area"), then `just diff --module <Module>`. A failure
     becomes a test, then its file is deleted.
<!-- differential:end -->
<!-- explore:begin -->
   - an explorer page (`Explore/README.md`, "Adding a page") where the feature is something a
     reader would want to try, then `just explore` and the page checked from `Explore/dist`.
<!-- explore:end -->
3. **A README example**, if the feature changes how the package is introduced, copied verbatim
   into `Tests/ProjectNameTests`.
<!-- benchmarks:begin -->
4. **A benchmark** in `Benchmarks/Benchmarks/<Module>Benchmarks` where speed matters, starting
   with a `BASELINE` entry: the hand-written form the code must keep pace with. Measure in
   release, and add a ratio test in `Tests/<Module>Tests/Performance/` where siblings have one.
   Use small inputs in debug builds, because the timing only runs in release.
   Judge a speed change by `just bench-simulated-compare --target <Module>Benchmarks`: its
   instruction, cache-miss and branch counts don't move when the machine is busy, as wall clock
   does. Allocation counts and absolute times still come from `just bench`, on a quiet machine.
   Re-record the `simulated` baseline for the targets a change touches
   (`just bench-simulated --target X`) and commit it with the change.
<!-- benchmarks:end -->

Watch for these:

- A closure inside `#expect` nested in another closure can run the wrong body, or crash the
  Linux compiler. Put the body in a nested `func`.
- Hoist literals to typed `let`s rather than writing them inline in `#expect`.
- Iterate dictionary keys sorted wherever order is visible.

### What to run

| Change | Run |
|---|---|
| Any library code | `bazel test` for every target in `bazel query 'rdeps(//Tests/..., //Sources/X)'`, then `just test-release` |
| `scripts/modules.py` | `just modules`, `just test` (which runs `//:package_swift_test`), `just spm` |
| A fuzzed module | `just fuzz-regress` <!-- fuzz:line --> |
| A module in `DIFFERENTIAL_DEPENDENCIES` | `just diff --module <Module>` <!-- differential:line --> |
| Integer arithmetic that could overflow, or anything platform-conditional | `just wasi-test -c release --targets XTests` (a 32-bit `Int`) <!-- wasm:line --> |
| `Benchmarks/`, or an API the benchmarks call | `cd Benchmarks && env -u TOOLCHAINS xcrun --toolchain default swift build -c release` <!-- benchmarks:line --> |
| A change meant to be faster | `just bench-simulated-compare --target <Module>Benchmarks`, not `just bench-compare` <!-- benchmarks:line --> |

### Pushing

Push finished work to `main` yourself; don't wait to be asked, and never end a task with
<!-- ci:begin -->
finished commits unpushed. Every push to `main` releases a patch version, and CI minutes are
scarce, so push once per batch rather than once per commit: when the work the owner gave you is
done (the whole request, or Ready is empty when working the backlog), push everything it
produced together.
<!-- fly:begin -->
Every push also deploys to Fly.io.
<!-- fly:end -->

1. Verify the committed state in a clean worktree: `bazel test //...` in debug, then
   `--config=release`.
2. Push, then watch the Release and DocC workflows to green, and fix anything that breaks.
3. Don't add CI steps that rebuild without the owner's approval.
<!-- ci:end -->
<!-- !ci:begin -->
finished commits unpushed. Push once per batch: when the work the owner gave you is done (the
whole request, or Ready is empty when working the backlog), push everything it produced together.
There is no CI, so nothing checks a push but you: verify the committed state in a clean worktree
first, `bazel test //...` in debug, then `--config=release`.
<!-- !ci:end -->

## House rules

### Code (*default*)

- **Declarative and composable.** Describe what a value is, not the steps that build it. Prefer
  small types and functions that compose (modifiers returning a new value, result builders,
  protocol extensions) over flags, configuration objects and long imperative bodies. A caller
  should be able to read an expression top to bottom and know the result.
- **Don't reinvent the wheel.** If the Swift ecosystem already has it, use it. Before writing a
  data structure, algorithm, parser, concurrency primitive or test tool, look in this order:
  1. The owner's libraries (Building blocks above).
  2. Apple: the standard library and Foundation, then Apple's open-source packages
     (swift-collections, swift-algorithms, swift-async-algorithms, swift-numerics, swift-atomics,
     swift-system, swift-argument-parser, swift-log, swift-crypto, swift-nio), then
     the platform frameworks where every target, Linux CI included, has them. <!-- ci:line -->
     the platform frameworks where every target, Linux included, has them. <!-- !ci:line -->
  3. Well-maintained community packages (Mockable and swift-property-based are already the
     picks for mocks and property tests).

  Write it yourself only when nothing fits: the package can't support the platforms, can't meet
  a measured performance need, or would pull in far more than the job needs. Say which package
  was rejected and why in the commit message.
- Public types are value types. Mutation returns a new value or is a clearly named `mutating`
  method; no shared mutable state reached through globals.
- Use the standard library's `Atomic`/`Mutex` or swift-atomics for shared state. No hand-rolled
  atomics.
- Names come from established libraries or the literature, familiar programmer terms first.
  Never invent names. No synonym typealiases; one name per concept. Spell names out.
- Delete unused API rather than keeping it.
- No hooks or SPI added only for tests.
- Underscored Swift features (`@_spi`, `_modify`, `@_effects`, `@_exported`) are fine where they
  help. Apple private API is not: undocumented framework symbols, private selectors, private
  frameworks, anything App Review rejects.

### Tests (*default*)

- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`). Never XCTest.
- Each test is self-contained and portable: no assertion or setup helpers, not DRY; a test
  copied to another file still works. Shared fixture data in `ProjectNameTestSupport` is tolerated;
  shared assertions are not.
- Test names state the rule they pin ("The checked spelling throws EmptyName for an empty name").
- Tests may call underscored and `package` API.
- Test doubles come from [Mockable](https://github.com/Kolos65/Mockable): mark the protocol at the
  seam `@Mockable` and use the generated `Mock<Protocol>` with `given`, `when` and `verify`
  inside the test, rather than hand-writing doubles. With DependencyInjection, register the mock
  inside the test's `withTestContainer { }`. Mocks exist only in debug builds, so a
  `PerformanceTests` target never uses one.
- Property tests use swift-property-based (`import PropertyBased`, `propertyCheck`).
- Randomized tests are seeded (`SeededRandomNumberGenerator`) so a failure reproduces from its
  seed alone.

### Docs (*default*)

- Describe the current API. No history ("previously", "renamed"), design debates, comparisons
  with other libraries, or benchmark numbers in doc comments or READMEs. Complexity bounds are
  fine.
- Doc comments: a one-line summary, then parameters, return value, complexity, and what traps or
  throws.
- The README's examples are tests (`Tests/ProjectNameTests`).

### Git (*default*)

- Commit message style: `[main] - <summary>`, no trailers (no co-author or session lines).
- One commit per finished feature or fix, after its suites pass.
- Never file bugs with third-party projects; record them locally.

## API conventions (*default*)

### Errors

- **Plain spellings trap** on a precondition failure, like an `Array` subscript. They are the
  fast path.
- **`checked:` spellings throw** a typed, payload-free error (`Greeting(checkedName:)` throws
  `EmptyName`). There are no nil-returning variants; `try?` gives `nil`.
- **Invariant-breaking mutations throw on the plain spelling** and change nothing, with one typed
  error per invariant whose cases make a single `catch` exhaustive.
- **Queries whose failure is the answer return a witness** (`findCycle() -> Cycle?`), not an
  error.

### Shapes

- Results are dedicated types, not tuples.
- Lazy views end in `View`; the materialized form drops the suffix.
- Materializing operations are static factories on a target the caller picks.

### Performance patterns

- Public types are copy-on-write structs, `@frozen`, with `@usableFromInline` internals.
  Hot generic code is `@inlinable`; parameters are `some` generics, never `any`.
- Copy-on-write: the uniqueness check is inlined and the reallocation slow path is
  `@inline(never)`. Bulk mutations check uniqueness once, outside the loop.
- Traps measured in past projects: nested functions capturing mutable locals (boxed, retained
  per step); generic iterators stored in arrays (use integer cursors); reading a struct out of a
  class property (copies and retains); lazy maps capturing `self`.
- Write overflow guards as comparisons (`x <= Int.max / 4`), not a discarded
  `multipliedReportingOverflow` result.
