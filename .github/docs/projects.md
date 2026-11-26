# What a new project has

- Two build systems from one table: Bazel for development (fast incremental builds, a remote
  cache, an Xcode project generated from the graph); SwiftPM for publishing. `scripts/modules.py`
  lists the modules, their dependencies and test targets, and writes `Package.swift` and every
  `BUILD.bazel`; a test fails if the two disagree.
- A justfile with the same commands in every project: `just test`, `just docs`,
  `just generate`, `just bench`.
- A remote cache with no setup per project: store a BuildBuddy API key in the Keychain once
  (`just buildbuddy-key`) and every project's builds use BuildBuddy's cache and build results;
  `just ci-secrets` gives a repository's CI the same key with `gh`; without it, CI's Bazel jobs
  build uncached and each run carries a warning that says so. The key is never written to a file.
- Strict defaults: Swift 6 language mode, first-party warnings as errors, a debug and a release
  configuration that don't throw away each other's cache.
- Tests with Swift Testing, including an example module (`Greetings`) that shows the house
  style: hand-worked cases, edge cases, a test of each thrown error (exit tests for traps with
  `--performance`), a property test against a naive reference, a seeded random number generator
  for reproducible failures.
- DocC for every module, merged into one site and published to GitHub Pages.
- CI on GitHub Actions: tests on every branch and pull request; every push to `main` that
  passes is tagged and released as the next patch version.
- Agent instructions: `AGENTS.md` (which `CLAUDE.md` includes) tells a coding agent the
  layout, the commands, the feature checklist and the house rules, so agents build the project the
  way the owner would.
- Mutation testing (optional): planted bugs per module, compiled into one build behind
  runtime switches, and a report of any the tests let through.
- Fuzzing (optional): a libFuzzer target per module in a separate package, checking the
  code against a simple model, with a local corpus each run resumes from.
- Differential testing (optional): seeded random cases answered by the library and by pinned
  reference implementations run through `uv`, with every disagreement saved to reproduce.
- WebAssembly tests (optional, libraries): the test suites built for wasm32-wasi and run under
  wasmtime, where `Int` is 32 bits.
- A browser explorer (optional, libraries): pages that run the library as WebAssembly, with
  the code each runs beside it, published next to the docs.
- SwiftUI views (optional, libraries): a view module for macOS and iOS with ViewInspector view
  tests, snapshot tests on the Mac, and SwiftLint and a11y-check (`just lint`).
- Benchmarks (optional): a separate package on
  [ordo-one/benchmark](https://github.com/ordo-one/benchmark), with wall-clock baselines and,
  with BenchmarkHarness (a separate tool, checked out alongside), simulated instruction and cache
  counts that stay steady on a busy machine.

A server adds a Vapor application, a production Docker image, a k6 load test against that image
(`just load`) and, optionally, Fly.io deployment and a SQLite database replicated with Litestream.

Firmware adds an ESP-IDF project whose app is Embedded Swift. Its logic lives in ordinary modules:
tested on the Mac, and also compiled by Bazel as Embedded Swift for the chip, so `just test` catches
code the chip can't run. `just firmware` builds the image and `just flash` flashes it.

An MCP server adds a `Tools` module (a `ToolServer` and a typed `ToolHandler` per tool, tested
through a real client over an in-memory transport), an executable serving them over stdio, and
`just install`, which puts the optimized binary where `claude mcp add` points.

An app adds an iOS app in SwiftUI built in layers: a `GreetingService` behind a `@Mockable`
protocol, a `DesignSystem` of light and dark tokens, and a `GreetingFeature` screen whose state is
one enum. Its view tests run in the simulator under ViewInspector with an injected `TestClock`;
snapshot tests pin each state in light, dark and two Dynamic Type sizes; one XCUITest smoke-tests
the built app (`just smoke`); and `just lint` runs SwiftLint and a11y-check. It has no CI: the
workflows run in Linux containers, and an iOS app's tests need a Mac.


## Types

| Type | What it adds |
|---|---|
| `library` (default) | Nothing: the template as it stands. A Swift package published through SwiftPM, with README examples as tests (`Tests/ProjectNameTests`). |
| `server` | `templates/server/` on top: a Vapor `App` module (`configure(_:)`, routes), a `ProjectNameServer` executable, `AppTests` (VaporTesting), a Dockerfile building with SwiftPM pinned by `swift/Package.resolved`, `just run`, `just docker`, and a k6 load test (`LoadTests/load.js`, `just load`) against a fresh production image. Platforms narrow to macOS; the README's installation section and README tests are dropped. |
| `mcp` | `templates/mcp/` on top: a `Tools` module on the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (`ToolServer`; `ToolHandler`, whose work takes `Decodable` arguments and returns or throws `Encodable` values, sent as structured content and as JSON text; an example `greet` tool), `ToolsTests` against a real client over `InMemoryTransport`, a `ProjectNameMCP` executable (swift-argument-parser) serving them on `StdioTransport`, `just run`, and `just install` into `~/.local/bin/projectname-mcp`. Platforms narrow to macOS; the README's installation section and README tests are dropped, and the README says how to register the server with `claude mcp add`. |
| `app` | `templates/app/` on top: an iOS app in SwiftUI (`Apps/ProjectName`, an `ios_application` holding only the composition root), a `GreetingService` module (a `@Mockable` protocol, `_GreetingService`, a `Container` factory) tested on the Mac, and two iOS modules (`IOS_MODULES` in `scripts/modules.py`), `DesignSystem` and `GreetingFeature`, which Bazel builds for the simulator and Package.swift leaves out. `GreetingFeatureTests` runs in the simulator: ViewInspector tests with a `TestClock` under `withMainSerialExecutor`, and snapshot tests through `tools/snapshots` (references in `__Snapshots__`, packaged into the bundle; `just record-snapshots`). DebugDrawer attached at the root view, opened on Control-D or a shake in debug builds and compiled to no-ops in release (`Apps/ProjectName/DebugDrawerTrigger.swift`). An XCUITest smoke test (`just smoke`), `just run`, and `just lint` (`tools/lint.bzl`: SwiftLint with `.swiftlint.yml`, and a11y-check), which `just test` runs first. No CI (`--ci` and `--trunk` are refused); the README's installation section and README tests are dropped. |
| `embedded` | `templates/embedded/` on top: `Firmware/`, an ESP-IDF project for the ESP32-C6 whose app (`Firmware/main`) is Embedded Swift; `tools/embedded.bzl`, which compiles every module in `FIRMWARE_MODULES` (`scripts/modules.py`) as Embedded Swift for the chip beside its host library (`//Sources/X:XEmbedded`, built by `bazel build //...`) and gathers them as `//Firmware:Modules`; and `tools/embedded-swift`, the one swift.org toolchain both builds use. `just firmware`, `just flash`, `just monitor`, `just menuconfig`, `just firmware-size`. Platforms narrow to macOS; the README's installation section and README tests are dropped. |

## Options

| Option | Adds |
|---|---|
| `--benchmarks` | `Benchmarks/`: a separate SwiftPM package, `BASELINE` entries, `just bench`, `bench-baseline`, `bench-compare`, and `bench-simulated` / `bench-simulated-compare` (Callgrind in a Linux VM through BenchmarkHarness, a separate tool expected at `~/workspace/BenchmarkHarness` or `$BENCHMARK_HARNESS`). The `main` and `simulated` baselines are committed. |
| `--mutation` | `scripts/mutate.py` and `just mutate <Module>`: the planted bugs in `scripts/mutants/<Module>.py` (a `Greetings` example), compiled into one build of a scratch copy behind runtime switches; each must make a test fail. Results are stored by a hash of everything a mutant depends on, so a rerun tests only what changed; `--select` runs coverage-selected tests first. |
| `--fuzz` | `Fuzz/`: a separate SwiftPM package of libFuzzer targets (a `FuzzGreetings` example checking `Greeting` against a model), `scripts/fuzz.py`, `just fuzz [Target] [-t secs]` (time-boxed, every target at once), `just fuzz-regress` (replays the local corpus) and `just fuzz-repro <target> <crash>`. Built with a swift.org toolchain through swiftly, in release with AddressSanitizer. The corpus and crashes stay local. |
| `--differential` | `Differential/`: an executable answering JSON cases with the library (built through Bazel in release, or `--swiftpm`), `scripts/differential.py` (seeded cases, references pinned and run through `uv`, failures saved to `Differential/Failures/` with their seed) with one file per area (a `differential_greetings.py` example against the `regex` package's grapheme clusters), and `just diff [--module X] [--cases N] [--seed S]`. |
| `--wasm` (library, embedded) | `scripts/wasi_test.py` and `just wasi-test [-c release] [--targets X,Y]`: the SwiftPM test targets built with swiftly's toolchain and Swift SDK for WebAssembly, run under wasmtime in groups (`Package.swift` declares only a group's targets when `<PROJECT>_WASI_TESTS` is set, and leaves out exit-test files). A 32-bit `Int` check. |
| `--explore` (library) | `Explore/`: a SwiftPM package of ElementaryUI pages compiled with the library to WebAssembly (a `greetings` example page), each drawn into its HTML at build time and mounted live in the browser, with code panels taken from the page's own sources. `just explore` builds `Explore/dist`; an `explore` job in `docc.yml` (WebAssembly SDK and wasm-opt cached) publishes it at `<pages>/explore/`, and keeps the live copy when it fails to build. |
| `--views` (library) | `templates/views/` on top: `GreetingsUI`, a SwiftUI view module (`GreetingCard`) in `MODULES`, Package.swift and the umbrella like any other, with its sources under `#if canImport(SwiftUI)` so Linux (CI, the docs) builds it empty; `GreetingsUITests` on the Mac: ViewInspector view tests and snapshot tests drawn by `ImageRenderer` in light and dark, their references in `__Snapshots__` beside the tests (in the test's runfiles under Bazel, which the generator adds for any test target on SnapshotTesting) and recorded through SwiftPM (`just record-snapshots`). The view-test packages are `APPLE_ONLY_PACKAGES`, and `GreetingsUITests` is in `APPLE_ONLY_TESTS`, which Bazel skips off macOS. `just lint` (`tools/lint.bzl`: SwiftLint and a11y-check, shared with the app type), which `just test` runs first. No DependencyInjection or Mockable: a view takes values. With CI, `docc.yml` builds the docs on a `macos-26` runner (Xcode through setup-xcode) instead of the Linux container, so the published site has the views' API; the other workflows stay on Linux. |
| `--examples` (library) | `templates/examples/` on top: `Examples/`, a hand-written SwiftPM package that depends on the library by path, so the published package never depends on what the examples use. `ExampleViews` (a SwiftUI `ExampleView` and `Greeting.example`) and its tests (`just examples-test`); `Examples/Apps/ExampleApp`, one `@main` source built by `ios_application` (iPhone and iPad), `macos_application`, `visionos_application` and `watchos_application`, every Bazel target there `manual` so `bazel test //...` builds none (`just example-ios`, `-mac`, `-visionos`, `-watchos`, `just examples`). The root BUILD.bazel lists the apps in `APP_TARGETS`, so `just generate` gives each a scheme; being `manual`, they build in no `bazel test //...`, Linux CI's included. No Mac Catalyst: rules_apple has no rule for it (AGENTS.md). |
| `--ios` (library, server) | `templates/ios/` on top: `Apps/ProjectName`, an `ios_application` showing a `Greeting`, tagged `manual` so `bazel build //...` and `bazel test //...` leave it out (Linux CI has no iOS toolchain, and the rule builds itself for iOS, where `target_compatible_with` can't tell the host apart); the justfile's `build` and `test` name it on a Mac, `just run` (a server's: `just run-app`) launches it in the simulator, and `APP_TARGETS` gives it an Xcode scheme. With it, the `simulator` piece the app type also has: `templates/simulator/` (`tools/test_host`, `tools/ui_test`), `.bazelrc`'s simulator settings and the generated `tools/ios.bzl`, so `IOS_MODULES` and simulator tests work as in the app type, and every `ios_unit_test` is incompatible off macOS, so Linux CI skips it. A project made without it gets it with `./template.py add <project> --ios`. |
| `--simulator` (library, server) | `templates/simulator/` alone: `tools/test_host`, `tools/ui_test` (the runner a UI test takes, which uninstalls its app first so the run can't keep an earlier build), the simulator settings in `.bazelrc` and the generated `tools/ios.bzl`, without an app, so `SIMULATOR_TESTS` (and `IOS_MODULES`) run in the simulator under `just test` on a Mac. `--ios` brings the same piece; `./template.py remove --ios` takes it away unless the stamp has `--simulator` too. |
| `--performance` (library, server) | The error convention of a high-performance library, for an API that runs in its callers' hot loops (see the template's README for when it fits; if in doubt, leave it off). Without it, plain spellings throw a typed error (`Greeting(name:)` is `throws(EmptyName)`), nothing traps at run time, and AGENTS.md's Errors section says so. With it: plain spellings trap on a precondition failure and `checked:` spellings throw (`Greeting(checkedName:)`), `Tests/GreetingsTests/GreetingExitTests.swift` pins the trap, `Greeting` is `@frozen` and `@inlinable`, and AGENTS.md keeps the trap and `checked:` bullets, the feature checklist's `checked:` and exit-test items, and Performance patterns. The Greetings samples of the other options (benchmarks, mutants, fuzz target, differential area, explorer page, views, examples, server route, iOS app) follow the same variant. |
| `--fly` (server) | `fly.toml` (suspend when idle, `/health` checks), a `deploy` job in `Release.yml` after CI (`FLY_API_TOKEN` secret), `just deploy`. Without it nothing deploys. |
| `--database` (server) | Fluent with SQLite in WAL mode: the file at `DATABASE_PATH`, memory when unset (production refuses to start without it); an example model and migration; a volume mount in `fly.toml`. |
| `--fly --database` | Litestream: `litestream.yml` replicates to Backblaze B2 (the `B2_*` Fly secrets), and `scripts/docker-entrypoint.sh` restores the database onto an empty volume, then runs the server under `litestream replicate`. Without the secrets it serves unreplicated. With one machine and one volume, Litestream runs directly, without LiteFS. |
| `--no-ci` | Leaves out `.github/workflows/` (CI, PR CI, Release, DocC; `templates/ci/` here) and everything that leans on it: `just ci-secrets`, the documentation link, the release and push rules in AGENTS.md. With `--fly`, `just deploy` is the only deploy; with `--explore`, `just explore` builds the site locally and nothing publishes it. CI is the one option on by default, and the only question asked as [Y/n]. |
| `--trunk` (with CI) | `.trunk/trunk.yaml`: pull requests merge through [Trunk's merge queue](https://docs.trunk.io/merge-queue), which waits for the checks it names (`Bazel tests` and `SwiftPM tests`, which CI runs on Trunk's `trunk-merge/` branches as on every branch but `main`). AGENTS.md's push rules become: a branch, a pull request, a `/trunk merge` comment. Install Trunk's GitHub app and turn the queue on for `main`; branch protection should require `ci / Bazel tests` and `ci / SwiftPM tests`. |


## Requirements

Every project needs macOS with Xcode's Swift 6.3 toolchain, and `bazelisk` and `just` from
Homebrew. The rest depends on what you turn on:

| For | You need |
|---|---|
| Benchmarks | `jemalloc` |
| A server | Docker, and `k6` for the load test |
| Fly.io deployment | `flyctl` |
| `just ci-secrets` | `gh`, signed in |
| Fuzzing | `swiftly` with a swift.org toolchain (`swiftly install 6.3.3`): Xcode's has no libFuzzer runtime |
| Differential testing | `uv` |
| WebAssembly tests | swiftly's toolchain, its Swift SDK for WebAssembly, and `wasmtime` |
| The explorer | swiftly's toolchain and WebAssembly SDK, and `binaryen` for `wasm-opt` |
| Firmware | swiftly's Swift 6.3.3 (Xcode's has no Embedded Swift for RISC-V), and [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/get-started/) 5.5 in `~/esp/esp-idf` or `IDF_PATH` |
| An app, `--ios` or `--simulator` | An iOS 18 simulator runtime in Xcode (the device and runtime `.bazelrc` names) |
