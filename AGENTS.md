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
Plugins/<Plugin>/                SwiftPM command plugins (PLUGINS in scripts/modules.py); Bazel builds none
Tests/<Module>Tests/             One test target per module; Performance/ holds speed-reliant tests
Sources/App/                     The Vapor application: configure(_:), routes, models <!-- server:line -->
Sources/ProjectNameServer/       The executable (@main): builds an Application, configures, serves <!-- server:line -->
Sources/Tools/                   The MCP server: ToolServer, and a ToolHandler per tool with its arguments and result <!-- mcp:line -->
Sources/ProjectNameMCP/          The executable (@main), projectname-mcp: serves the tools over stdio <!-- mcp:line -->
Sources/GreetingService/         The service the screen asks: a @Mockable protocol, its _GreetingService, a Factory <!-- app:line -->
Sources/DesignSystem/            Color and font tokens for light and dark mode and Dynamic Type (iOS) <!-- app:line -->
Sources/GreetingFeature/         The greeting screen, GreetingView (iOS) <!-- app:line -->
Apps/ProjectName/                The iOS app: the composition root, Info.plist, the ios_application, and the debug drawer's trigger <!-- app:line -->
Apps/ProjectNameSmokeTests/      The one XCUITest, against the built app (`just smoke`) <!-- app:line -->
tools/snapshots/                 assertBazelSnapshot: snapshot references read from the test bundle under Bazel <!-- app:line -->
tools/test_host/                 The empty app every simulator test runs inside, so windows get a scene <!-- app:line -->
tools/iphone/                    The scripts `just phone-install` and `just phone-provision` run, and their test <!-- app:line -->
Sources/GreetingsUI/             GreetingCard, a SwiftUI view of a Greeting for macOS and iOS <!-- views:line -->
Tests/GreetingsUITests/          Its ViewInspector and snapshot tests, run on the Mac; __Snapshots__ the references <!-- views:line -->
tools/lint.bzl                   `just lint`: SwiftLint (.swiftlint.yml) and a11y-check over first-party targets <!-- swiftui:line -->
Tests/ProjectNameTests/          The README examples, verbatim <!-- library:line -->
Tests/ProjectNameTestSupport/    Shared test fixtures (data only)
scripts/modules.py               The module graph
scripts/mutants/<Module>.py      Planted bugs for `just mutate <Module>` (scripts/mutate.py) <!-- mutation:line -->
Fuzz/Sources/Fuzz<Module>/       A libFuzzer target per module, in the separate Fuzz/ package <!-- fuzz:line -->
Differential/                    The library side of `just diff`; scripts/differential_<area>.py the references <!-- differential:line -->
Explore/                         The browser explorer: pages running the library as WebAssembly (`just explore`) <!-- explore:line -->
Examples/                        The example apps, a SwiftPM package of their own; Apps/ExampleApp the Apple apps Bazel builds <!-- examples:line -->
Firmware/                        The ESP-IDF project: main/ is the app; BUILD.bazel gathers the modules it imports <!-- embedded:line -->
tools/                           Bazel rule wrappers (warnings as errors, Swift 6 mode), DocC rules;
                                 tools/bazel turns BuildBuddy on when the Keychain holds its key, and
                                 on macOS sweeps stale output bases once a day (tools/sweep-output-bases):
                                 a deleted workspace's, or one idle 7 days
tools/embedded.bzl               Modules compiled as Embedded Swift, through tools/embedded-swift's toolchain <!-- embedded:line -->
Dockerfile                       The production image, built with SwiftPM <!-- server:line -->
LoadTests/load.js                The k6 load test that `just load` runs against the image <!-- server:line -->
fly.toml                         The Fly.io app <!-- fly:line -->
.trunk/trunk.yaml                The checks Trunk's merge queue waits for before it merges to main <!-- trunk:line -->
litestream.yml                   SQLite replication to B2; scripts/docker-entrypoint.sh runs it <!-- litestream:line -->
```

<!-- benchmarks:begin -->
`Benchmarks/` is a separate SwiftPM package (ordo-one/benchmark), generated from `BENCHMARKS` in
`scripts/modules.py`. Bazel builds none of it; `Benchmarks/BUILD.bazel` only caches each target's
simulated counts (`tools/benchmarks.bzl`). See `Benchmarks/README.md`.
<!-- benchmarks:end -->
<!-- fuzz:begin -->
`Fuzz/` is a separate SwiftPM package of libFuzzer targets that Bazel ignores, built with a
swift.org toolchain through swiftly (`swiftly install 6.3.3`); see `Fuzz/README.md`.
<!-- fuzz:end -->
<!-- examples:begin -->
`Examples/` is a separate SwiftPM package of example apps that depends on the library by path, so
the published package never depends on what the examples use. Its `Package.swift` and its few
`BUILD.bazel` files are hand-written, not generated: SwiftPM builds and tests it
(`just examples-test`), and Bazel builds only the Apple apps (`Examples/Apps/ExampleApp`: iPhone and
iPad, Mac, visionOS, watchOS), every target `manual`, so `just test` never builds them, on a Mac
or on Linux. The root BUILD.bazel lists them in `APP_TARGETS`, so `just generate` gives each an
Xcode scheme. rules_apple has no Mac Catalyst rule: the Mac app stands in for it, and a
Catalyst build would have to come from SwiftPM (`--triple arm64-apple-ios18.0-macabi`) outside
Bazel. See `Examples/README.md`.
<!-- examples:end -->

### Module graph

`scripts/modules.py` is the source of truth for modules, their dependencies, test targets,
external packages and platforms. `just modules` regenerates `Package.swift`, every `BUILD.bazel`,
the umbrella module and `swift/Package.swift` from it. Never edit the generated files by hand;
`//:package_swift_test` fails when `Package.swift` disagrees with the Bazel graph.
`just modules` refuses a table or function defined twice in it, which a template update can merge
in beside the project's own: keep one definition, holding the project's rows, and delete the other.

- Add a module: a row in `MODULES` (name, group, description, dependencies), then `just modules`.
- Add a test target: a row in `TEST_TARGETS`. A target with a `Performance/` directory of Swift
  sources must be listed in `PERFORMANCE_TESTS`, and the reverse.
- Run a test target in the iOS simulator as well (the tests of a module every platform builds that
  holds code under `#if canImport(UIKit)`): its name in `SIMULATOR_TESTS`, then `just modules`. It
  stays in Package.swift and keeps its run on the Mac and Linux, and gains
  `//Tests/<Target>:<Target>Simulator`, an `ios_unit_test` of the same tests inside
  `tools/test_host`, which `just test` runs on a Mac and Linux skips. Its UIKit tests sit under
  `#if canImport(UIKit)`, and its exit tests under `#if !os(iOS)`, as iOS has none. At least one
  test must run on the Mac, since Bazel's runner fails a run of none; a target whose Mac tests are
  Apple's alone goes in `APPLE_ONLY_TESTS` too. A target that depends on an iOS module or a Bazel
  label runs in the simulator alone already, so it isn't listed.
  The app type ships the test host; any other copies `tools/test_host` and the simulator lines of <!-- !app:line -->
  `.bazelrc` from an app render first (`just modules` refuses the table without them). <!-- !app:line -->
  `just mutate` runs a spec's simulator targets through Bazel (`scripts/mutate.py`). <!-- mutation:line -->
- Give a test target an environment variable under `bazel test` (an integration test that runs
  only when `TEST_DATABASE_URL` is set, say): its name and the variables in `TEST_ENVIRONMENT`
  (`{"<Target>Tests": ["TEST_DATABASE_URL"]}`), then `just modules`. Bazel strips the test
  environment; the generator writes the names as `env_inherit` on that target's `swift_test`, its
  Performance one and its simulator `ios_unit_test`, so only those targets see the variable and
  only their cached results depend on it. Not `--test_env` in `.bazelrc`, which hands it to every
  test. SwiftPM passes the whole environment already. `check()` refuses a name that isn't a test
  target.
- Add an executable: a row in `EXECUTABLES` (name, description, dependencies). It holds only
  `@main`; its code lives in a module, where tests reach it.
- Add an example module (a demo app's views, a sample server's routes): a row in `MODULES` and its
  name in `EXAMPLE_MODULES`, then `just modules`. It builds and tests like any module, but has no
  library product, umbrella import or DocC archive, so neither it nor its dependencies ship. Only
  executables, test targets and other example modules may depend on it (`check()` enforces it).
- Offer a module on its own but not through `import ProjectName` (a test-support back end, such as
  an in-memory store adopters use in their tests): its name in `NON_UMBRELLA_MODULES` too, then
  `just modules`. It keeps its library product and DocC archive; only the umbrella leaves it out.
  The umbrella catalog's topic list is hand-written: list it there under a heading of its own, not
  among the production modules.
- A library module that imports Swift Testing (a helper adopters add to their test targets: a
  custom `Trait`, an assertion that records an `Issue`): its name in `TESTING_MODULES` and
  `NON_UMBRELLA_MODULES` too, then `just modules`. Bazel finds Testing only on the developer search
  paths, which rules_swift gives testonly targets alone; the generator gives them to its
  `swift_library` and its docs' symbol graph. A module that depends on it must be listed too, and no
  executable may (`check()` enforces both).
- Give a module resources (data files, Apple's privacy manifest): put them under `Sources/<Module>/`
  and list each in `RESOURCES` (`{"<Module>": [("process", "Data/x.json"), ("copy", "Fixtures")]}`,
  paths relative to the module, rules as SwiftPM's `.process` and `.copy`), then `just modules`.
  Package.swift gets `resources:`, and Bazel the same `ProjectName_<Module>.bundle`
  (`tools/resources.bzl`): nested in an app's or test bundle's resources on Apple platforms, in the
  runfiles of `bazel test` and `bazel run` on macOS and Linux, found by a generated `Bundle.module`.
  The module reads them through `Bundle.module` under either build system, and its tests read them
  through the module. Bazel processes `process` files only inside Apple bundles (strings, asset
  catalogs); elsewhere they are copied as they are, as SwiftPM does off Apple platforms. A module
  that calls a required-reason API or collects data ships `PrivacyInfo.xcprivacy`, listed as
  `("copy", "PrivacyInfo.xcprivacy")` so it sits at the bundle's root; `check()` refuses one left
  out, a listed path that doesn't exist, and one inside another listed directory.
  A firmware module can't have resources: Embedded Swift has no bundles. <!-- embedded:line -->
- Add a macro: its compiler plugin is a row in `MACROS` (name, group, description, and only
  package products as dependencies: swift-syntax's, with `swift-syntax` in `PACKAGES`), its sources
  in `Sources/<Plugin>/` (an `@main` `CompilerPlugin` listing the macro types), then `just modules`
  and `just resolve`. The module that declares the macros (`#externalMacro(module: "<Plugin>",
  type: ...)`) lists the plugin among its dependencies: Package.swift gets a `.macro` target, Bazel
  a `swift_compiler_plugin` in that module's `plugins`. The plugin has no product, docs or umbrella
  import; adopters import the declaring module, and build swift-syntax with it, so when the package
  has an umbrella, consider `NON_UMBRELLA_MODULES` for it. A test target that lists the plugin tests
  its expansions (`assertMacroExpansion` from `SwiftSyntaxMacrosGenericTestSupport`, with
  `Issue.record` as its failure handler); one that lists the declaring module tests the expanded
  code. A source that must not compile (a macro's diagnostic as the compiler reports it) is a
  `swift_compile_failure_test` (`tools/compile_failure_test.bzl`) in `Tests/CompileFailures`, a
  hand-written BUILD.bazel no Package.swift target holds, with a control that compiles.
  A plugin takes planted bugs like a module (`scripts/mutants/<Plugin>.py`), with its expansion <!-- mutation:line -->
  tests as the spec's `TESTS`. <!-- mutation:line -->
- Add a command plugin (`swift package <verb>`): a row in `PLUGINS` (name, verb, description, and
  the reason it writes to the package directory, or `None` when it writes nothing there), its
  sources in `Plugins/<name>/` (an `@main` `CommandPlugin`), then `just modules`. Package.swift gets
  a `.plugin` target and product; Bazel builds none of it, so no test reaches the plugin. Keep it
  thin, its logic in a module or an executable it builds and runs, and run it on the package
  (`swift package --allow-writing-to-package-directory <verb>`) after a change to it.
- Add an external package: a row in `PACKAGES`, its `swiftpkg_<identity>` repository in
  `MODULE.bazel`'s `use_repo`, then `just modules` and `just resolve`.
- Generate mocks: uncomment the Mockable row in `PACKAGES`, add `mockable/Mockable` to the
  module that declares the protocol and to its test target, add `swiftpkg_mockable` to
  `use_repo`, then `just modules` and `just resolve`. The generator defines `MOCKING` for that
  module in debug builds only, in both build systems.
- A package whose main module takes the project's name (`import ProjectName` is the library
  itself) lists it in `MODULES`; the generator then writes no umbrella.
- A package only Apple platforms build (Objective-C, a wrapper of an Apple framework) goes in
  `APPLE_ONLY_PACKAGES` too: its products are linked on Apple platforms only, so the targets still
  build on Linux, and the code that uses them sits under `#if canImport(...)`.
<!-- wasi:begin -->
- A package that builds everywhere but WebAssembly (one on NIOPosix: Hummingbird, Vapor) goes in
  `NON_WASI_PACKAGES` too: its products are linked on every other platform, so the package still
  builds for wasm32-wasi, and the code that uses them sits under `#if canImport(...)`.
<!-- wasi:end -->
- Raise the Swift floor (a dependency's manifest needs a newer Swift): set `SWIFT` (every
  manifest's tools version, CI's and the Docker image's Swift, the minimum the docs state) and
  `SWIFT_TOOLCHAIN` (the swift.org release swiftly installs where Xcode's toolchain falls short)
  in `scripts/modules.py`, then `just modules`. It writes them into the generated manifests and
  replaces the previous ones in every other file that names them (`SWIFT_SITES`), from the record
  in `tools/swift_version.bzl`. Never edit a version in those files by hand. `just template-update`
  keeps the project's versions, and says when the template's have passed them.
  The fuzz targets build with `SWIFT_TOOLCHAIN`. <!-- fuzz:line -->
  `just wasi-test` builds with `SWIFT_TOOLCHAIN` and its WebAssembly SDK. <!-- wasm:line -->
  The explorer builds with `SWIFT_TOOLCHAIN` and its WebAssembly SDK. <!-- explore:line -->
  The firmware builds with `SWIFT_TOOLCHAIN`'s Embedded Swift. <!-- embedded:line -->
  CI needs a `swift-bazel` image of the new version, published from the project template's <!-- ci:line -->
  `ci-image/build.sh`; with the explorer, `just modules` asks for docc.yml's `WASM_SDK_SHA256`. <!-- ci:line --><!-- explore:line -->
  `ci-image/build.sh`. <!-- ci:line --><!-- !explore:line -->
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
| `just examples-test`, `just example-ios` / `-mac` / `-visionos` / `-watchos`, `just examples` | The examples' tests (SwiftPM, in `Examples/`); build one Apple example app; every app, then the tests <!-- examples:line --> |
| `just test-release` | `--config=release`: builds and runs only the `XPerformanceTests` targets |
| `just spm-test`, `just verify` | SwiftPM tests; both build systems |
| `just modules` | Regenerate build files from `scripts/modules.py` |
| `just resolve` | Re-resolve Bazel's SwiftPM dependencies after editing `PACKAGES` |
| `just bench [--target X]` | Benchmarks; `just bench-compare` against the `main` baseline <!-- benchmarks:line --> |
| `just bench-simulated-compare [--target X]` | Simulated counts (Callgrind in a Linux VM, from `~/workspace/BenchmarkHarness`) against the committed `simulated` baseline; `just bench-simulated [--target X]` re-records it. Both measure only targets whose code changed <!-- benchmarks:line --> |
| `just docs` | Combined DocC site into `.build/docs` |
| `just generate` | Xcode project from the Bazel graph, in `xcode/` (out of the root, where `xcodebuild` would pick it over `Package.swift`) |
| `just buildbuddy-key`, `just ci-secrets` | Store the BuildBuddy key in the Keychain (once per Mac; builds then use the remote cache); set it as this repository's Actions secret with `gh` <!-- ci:line --> |
| `just buildbuddy-key` | Store the BuildBuddy key in the Keychain (once per Mac; builds then use the remote cache) <!-- !ci:line --> |
| `just template-update` | Merge the project template's changes since `.template.json`'s commit; resolve conflicts, then `just modules`, `just test` |
| `just run [args]` | The server on port 8080 (`bazel run //Sources/ProjectNameServer -- serve`) <!-- server:line --> |
| `just docker` | Build the production image and run it on port 8080 <!-- server:line --> |
| `just load [k6 args]` | Load-test a fresh production image with k6; `BASE_URL=… just load` for a running server <!-- server:line --> |
| `just deploy` | Deploy this checkout to Fly.io <!-- fly:line --> |
| `just firmware` | Build the firmware image: Bazel compiles the modules, ESP-IDF the app and the image <!-- embedded:line --> |
| `just flash [port]`, `just monitor [port]` | Flash the board on USB and show its log; the log alone (Ctrl-] quits either) <!-- embedded:line --> |
| `just menuconfig`, `just firmware-size` | Change ESP-IDF settings (saved to `Firmware/sdkconfig.defaults`); the image's size by component <!-- embedded:line --> |
| `just install` | Build the server optimized and install it as `~/.local/bin/projectname-mcp`, the binary `claude mcp add` registers <!-- mcp:line --> |
| `just run [args]` | The server over stdio (`bazel run //Sources/ProjectNameMCP`), waiting for a client <!-- mcp:line --> |
| `just run` | The app in the simulator (`bazel run //Apps/ProjectName`; .bazelrc names the device) <!-- app:line --> |
| `just lint` | SwiftLint and a11y-check over every first-party target; `just test` runs it first <!-- swiftui:line --> |
| `just smoke` | The XCUITest smoke test, launching the built app in the simulator <!-- app:line --> |
| `just phone-provision [udid]` | Once per new iPhone: Xcode's automatic signing registers it and makes the app's provisioning profile <!-- app:line --> |
| `just phone-install [udid]`, `just phone-install-release [udid]` | Install and launch a debug (or optimized) build on the connected iPhone, waiting up to `PHONE_UNLOCK_WAIT` seconds for it to be unlocked <!-- app:line --> |
| `just record-snapshots` | Re-record every snapshot reference after a change to how a screen looks <!-- app:line --> |
| `just record-snapshots` | Re-record every snapshot reference (through SwiftPM) after a change to how a view looks <!-- views:line --> |
| `bazel query 'rdeps(//Tests/..., //Sources/X)'` | Test targets affected by a change to X |

- Debug is the default configuration. Every test target except the `XPerformanceTests` ones is
  tagged `debug-only`, which `--config=release` filters out.
- A test that bounds wall-clock time, or runs a large input under `.timeLimit`, belongs in
  `Tests/X/Performance/`.
- Release builds use their own output base (see the justfile). Don't create other output bases
  or copies of the repo, and shut down any extra Bazel server you start.
- Run suites through Bazel, not `swift test --filter`.
- First-party warnings are errors (`tools/swift_rules.bzl`); dependencies build quietly. Fix the
  warning, never suppress it. DocC's are too: `just docs` fails on a link that doesn't resolve.
- CI's Bazel jobs run in `ghcr.io/tyler-keith-thompson/swift-bazel:<swift>-<bazel>`, Swift with <!-- ci:line -->
  the Bazel in `.bazelversion` already in it, built by the project template's `ci-image/build.sh`. <!-- ci:line -->
  Changing `.bazelversion` or the workflows' Swift version means a new tag from there. <!-- ci:line -->
  The package is private; a repository pulls it once added under its Manage Actions access. <!-- ci:line -->
- Exit tests (`#expect(processExitsWith:)`) go in files of their own, apart from the other tests: <!-- wasm:line -->
  builds for platforms that cannot start a child process leave those files out. <!-- wasm:line -->
- Exit tests (`#expect(processExitsWith:)`) go in files of their own, apart from the other tests. <!-- !wasm:line -->
<!-- wasm:begin -->

### 32-bit `Int` (WebAssembly)

watchOS's arm64_32 and wasm32 have a 32-bit `Int`. `just wasi-test` (`scripts/wasi_test.py`)
builds the SwiftPM test targets with `swift build --build-tests --swift-sdk
swift-6.3.3-RELEASE_wasm` through swiftly into `.build/wasm`, then runs each test binary (one
`<Target>-test-runner.wasm` per target from Swift 6.4, one `<Project>PackageTests.xctest` before)
with `wasmtime run --dir . --dir <checkout>::<checkout> --argv0 <binary's path> <binary>
--testing-library swift-testing`, logs in `.build/wasm/logs`. The checkout at its own path and the
binary's path as `argv[0]` are where SwiftPM's `Bundle.module` looks for a module's resource bundle
(an absolute build path in 6.3, beside `Bundle.main` from 6.4, which WASI's Foundation takes from
`argv[0]`).
Needs swiftly's 6.3.3 toolchain, its WebAssembly SDK (`swift sdk list`; swift.org's "Getting
Started with Swift SDKs for WebAssembly" has the install command) and `brew install wasmtime`. If
the toolchain crashes on the manifest against a newer Xcode's SDK, pass `--xcode
/Applications/Xcode-<older>.app`.

- One binary of every target can pass wasmtime's limit of a million functions, so targets run in
  groups (`<PROJECT>_WASI_TESTS`, the project's name in capitals, makes `Package.swift` declare
  only those).
- Not run on WASI: files with exit tests (no child processes; the manifest leaves them out), and
  anything needing threads (`#if !os(WASI)`).
- WASI runs every task on one thread, and a sleep that is cancelled still holds it until its
  deadline. A time limit's timer is such a sleep: the body runs, but the timer then holds the
  thread for the whole limit, so every `.timeLimit` test reports its limit exceeded. The script
  counts only the issues besides those. Tests run in parallel, so the timers overlap; `--serial`
  (Swift Testing's `--no-parallel`) costs each time-limited test its whole limit. A test that
  cancels a real-clock sleep waits it out the same way, which is one more reason code takes its
  clock from `Container` and tests advance a `TestClock`.
- Without wasm tail calls, an await that doesn't suspend deepens both stacks. The script links a
  64 MB stack and gives wasmtime a 256 MB one, enough for a 10,000-deep chain of such awaits; a
  deeper one traps or hangs on WASI alone.
- Foundation on WASI drops the last character of a resource's file name when the lookup names a
  subdirectory: `Bundle.module.url(forResource: "sample", withExtension: "txt", subdirectory:
  "Fixtures")` returns `Fixtures/sample.tx`, which doesn't exist, and so do
  `path(forResource:ofType:inDirectory:)`, `urls(forResourcesWithExtension:subdirectory:)` and a
  name holding the directory. Look up the directory itself, then append the file:
  `Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appending(path: "sample.txt")`.
- A dependency that doesn't build for WASI (NIOPosix and what sits on it) fails the whole build.
  List its package in `NON_WASI_PACKAGES` (`scripts/modules.py`), and put the code and tests that
  use it under `#if canImport(<its module>)`.
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
<!-- embedded:begin -->
## Firmware

The firmware's logic lives in ordinary modules, listed in `FIRMWARE_MODULES` (`scripts/modules.py`):
Bazel and SwiftPM build and test them on the Mac like any other, and Bazel also compiles each as
Embedded Swift for the chip (`//Sources/X:XEmbedded`, `tools/embedded.bzl`). `Firmware/` is the
ESP-IDF project. Its app, `Firmware/main`, is the only code that calls ESP-IDF; it imports the
modules from `//Firmware:Modules`, which the firmware build has Bazel build first.

- A firmware module must stay valid Embedded Swift: no Foundation, no `any` existentials (take
  `some` or a generic parameter), no reflection. `bazel build //...` compiles every firmware
  module for the chip, so `just test` fails on any of these.
- Firmware modules depend only on other firmware modules (`check()` in `scripts/modules.py`
  enforces it). External packages build for the host alone.
- Hardware sits behind protocols in the modules (a pin, a motor, a sensor), taken as generic
  parameters. The app implements them with ESP-IDF calls; tests drive the logic against a
  simulation of the device, written in the test target or `ProjectNameTestSupport`. Mockable can't
  build for the chip, so for hardware this replaces it: the one exception to the Mockable rule.
- Logic takes time and readings as inputs (a state machine the app's loop steps with the elapsed
  milliseconds), never a clock or a delay of its own, so tests run in simulated time.
- `Int` is 32 bits on the chip, 64 on the Mac. Pick integer types for the device's real ranges
  and guard arithmetic that could overflow.
  `just wasi-test` runs the suites with a 32-bit `Int`. <!-- wasm:line -->
- Keep `Firmware/main` thin: the protocols' ESP-IDF implementations and the loop. Each ESP-IDF
  component it calls goes in `PRIV_REQUIRES` in `Firmware/main/CMakeLists.txt`, and its header
  in `BridgingHeader.h`. Nothing tests it but `just firmware` and the board.
- The chip is `CONFIG_IDF_TARGET` in `Firmware/sdkconfig.defaults` and must be RISC-V (an
  ESP32-C or -H series, or the P4). Changing it means `MARCH` and `MABI` in `tools/embedded.bzl`
  too; the firmware build stops and prints the right ones when they differ.
- One Swift toolchain compiles the modules and the app: `VERSION` in `tools/embedded-swift`, a
  swift.org toolchain from swiftly (Xcode's has no Embedded Swift for RISC-V). The CI <!-- ci:line -->
  container in `.github/workflows/CI.yml` (`swift-bazel:<swift>-<bazel>`) is pinned to the same version; <!-- ci:line -->
  change both together. <!-- ci:line -->
- Anything that burns eFuses (secure boot, flash encryption, `idf.py efuse-*`) cannot be undone
  on that board. Never run it without the owner's go-ahead for that board.

<!-- embedded:end -->
<!-- mcp:begin -->
## MCP server

`Tools` is the server, a library so tests reach every tool; `ProjectNameMCP` only starts it on
`StdioTransport`. Claude Code launches the installed binary (`just install`) for each session.

- Standard output carries only MCP messages: any other byte there corrupts the stream and the
  client drops the server. Never `print`; diagnostics go to standard error, and a logger to
  `StreamLogHandler.standardError`. The SDK's own loggers write nothing unless given one.
- A tool is a `ToolHandler`: a name, a description written for the calling model, a JSON schema
  for its arguments and annotations, then work that takes a `Decodable` type and returns an
  `Encodable` one or throws an `Encodable` error. Results and errors encode as JSON objects. Add
  it to the `tools:` list in `Sources/ProjectNameMCP`, a row in the README's tool table, and tests.
- The schema and the `Decodable` type describe the same arguments; a test calls the tool with
  each argument wrong and expects `invalidArguments`.
- Annotations are promises the client acts on: `readOnlyHint` only when the tool changes
  nothing anywhere, `destructiveHint: false` only when no write can lose data, `idempotentHint`
  only when repeating a call changes nothing more, `openWorldHint` whenever the tool reaches past
  this machine. A test pins each tool's annotations.
- The calling model has other tools (a shell, the network), so a result is a channel into it.
  Text a tool didn't write itself (web pages, files, messages, other people's data) is untrusted:
  return typed values (numbers, enums, identifiers, URLs the server builds) rather than that text,
  and test that injection text in the input never reaches the output. A tool that must return
  untrusted text says so in its description. Errors name a reason, never echo the request.
- Secrets (API keys, tokens) come from the Keychain or the environment Claude Code passes
  (`claude mcp add -e`), never arguments, files in the repo or results.
- Tests run a real `Client` against the server over `InMemoryTransport.createConnectedPair()`, one
  server per test, and disconnect and stop it at the end.
- After a change to the executable or to what reaches standard output, `just install` and
  `claude mcp list` (or a new session) to see it connect.

<!-- mcp:end -->
<!-- app:begin -->
## App

The app is `Apps/ProjectName`: the composition root and nothing else. Screens live in feature
modules, which build on services, which hold no UI (Seams and composition, below).

- **The debug drawer** (DebugDrawer, Building blocks) is attached at the root view and opens on
  Control-D or a shake, in debug builds only. Debug-only tools are plugins installed from the
  composition root's `init()` (a plugin's product in the app's `BUILD.bazel`, its `install…()` call
  under `#if DEBUG`), never a screen or gesture of their own. Release builds compile it to no-ops.
- A module that imports SwiftUI or UIKit for its views goes in `IOS_MODULES` (`scripts/modules.py`)
  as well as `MODULES`. Bazel builds it for the simulator only; Package.swift, the umbrella and the
  docs leave it out, and anything that depends on it must be iOS too. A service stays out of
  `IOS_MODULES`, so its tests run on the Mac, fast, as `swift_test`.
- A test target that depends on an iOS module (or on a label such as
  `//tools/snapshots:BazelSnapshotTesting`) runs in the simulator as an `ios_unit_test` hosted by
  `tools/test_host`, with `__Snapshots__` packaged into its bundle. Package.swift leaves it out.
  A service whose module also holds UIKit code (`#if canImport(UIKit)`) keeps its tests on the Mac
  and runs them in the simulator too through `SIMULATOR_TESTS` (Module graph), rather than
  depending on a label to get there.
- **A view is a function of its state.** The state is one enum (`ViewState`) with a case per
  screen the view can show, set in one place from what the service returned. The view resolves its
  service and clock with `@ConstructorInjected`. Work starts in `.task` (`.task(id:)` restarts it
  when its input changes) and checks `Task.isCancelled` before writing state.
- **View tests** use ViewInspector: host the view (`ViewHosting.host`), act through
  `sut.inspection.inspect` (`setInput`, `tap`), advance the `TestClock`, then inspect what it shows.
  They run `@MainActor`, `.serialized`, under `withMainSerialExecutor`, each with its own
  `withTestContainer`. The view's `let inspection = Inspection<Self>()` and its `.onReceive` are the
  one hook production code carries for tests.
- **Snapshot tests** pin how each state renders: light and dark, and Dynamic Type at `.xSmall` and
  `.accessibility5`, through `assertBazelSnapshot`. A snapshot is worth only what a person reads in
  it, so look at every recorded image before committing it. After a change to how a screen looks,
  `just record-snapshots`, then review the changed images in `git diff`.
- **The smoke test** (`Apps/ProjectNameSmokeTests`) is the one XCUITest, and the one use of
  XCTest: launch the app, do the main thing, see the result. Everything else is proved by view and
  snapshot tests, which are fast and deterministic. `just smoke` after a change to the app target or
  to how screens connect.
- **On an iPhone**: `just phone-provision` once per new iPhone (Developer Mode on, the Mac trusted),
  then `just phone-install` (debug, with the debug drawer) or `just phone-install-release`. A device
  build (`--config=device`) signs with the development profile Xcode's automatic signing makes,
  found by its name, "iOS Team Provisioning Profile: <bundle id>"; keep `bundle_id` in
  `Apps/ProjectName/BUILD.bazel` and `PHONE_BUNDLE_ID` in the justfile in step. The team comes from
  `DEVELOPMENT_TEAM` in the environment, else from the Apple Development certificate Xcode puts in
  the Keychain once you sign in (Settings > Accounts). No team ID, certificate or profile is
  committed. A locked iPhone is waited for (`PHONE_UNLOCK_WAIT`, 1800 seconds), and a newer install
  ends an earlier one's wait; `tools/iphone/iphone_test.py` pins this against stand-in tools.
- **Accessibility**: every control has an `accessibilityLabel`; an image that only decorates is
  `accessibilityHidden(true)`; rows that read as one item combine (`.accessibilityElement(children:
  .combine)`); animations respect `accessibilityReduceMotion`; sizes that should grow with text use
  `@ScaledMetric`. `just lint` runs a11y-check over the views.
- **Design tokens**: colors and fonts come from `DesignSystem` (`Color.textPrimary`,
  `Font.titleBold`), each with light and dark values and a Dynamic Type text style, never a literal
  in a view.
- `just lint` (SwiftLint, `--strict`, `.swiftlint.yml` plus `.swiftlint-tests.yml` for tests) must
  pass; fix the code rather than disable a rule inline.

<!-- app:end -->
<!-- views:begin -->
## Views

Some modules hold SwiftUI views. The template's example is `GreetingsUI` (`GreetingCard`, a view
of a `Greeting`), to be replaced by the project's first real view module. View modules are ordinary
library modules: in `MODULES` and Package.swift, and in the umbrella module when the package has
one, built for macOS by Bazel and for every platform by SwiftPM.

- **Linux builds them empty.** SwiftUI is on Apple platforms alone, and CI builds on Linux, as can <!-- ci:line -->
  anyone who depends on the package, so a view module's sources sit under <!-- ci:line -->
- **Linux builds them empty.** SwiftUI is on Apple platforms alone, and anyone who depends on the <!-- !ci:line -->
  package can build it on Linux, so a view module's sources sit under <!-- !ci:line -->
  `#if canImport(SwiftUI)` and its tests under `#if os(macOS)`. The view-test packages
  (ViewInspector, SnapshotTesting, IssueReporting) are in `APPLE_ONLY_PACKAGES`, so Linux links
  none of them, and a test target of views alone is in `APPLE_ONLY_TESTS`, so Bazel skips it off
  macOS rather than fail a run of no tests.
  The DocC workflow runs on macOS, so the published site documents the views; the rest of CI <!-- ci:line -->
  stays on Linux. <!-- ci:line -->
- **A view is a function of its input.** It takes values (`GreetingCard(greeting:)`), keeps what
  it changes itself in `@State`, and holds no services: a view that needs one takes a closure or a
  value from the caller. When a screen can show several things, its state is one enum with a case
  per thing (Seams and composition). A module that grows a seam (network, disk, clock) puts it behind
  a protocol as that section says, in a module of its own below the views.
- **View tests** use ViewInspector on the Mac: host the view (`ViewHosting.host`), act through
  `sut.inspection.inspect` (`tap`, `setInput`), then inspect what it shows. They run `@MainActor`
  and `.serialized`. The view's `let inspection = Inspection<Self>()` and its `.onReceive` are the
  one hook production code carries for tests; the test target makes `Inspection` an
  `InspectionEmissary`. To run them in the iOS simulator as well, widen their guard to
  `#if os(macOS) || os(iOS)` and list the target in `SIMULATOR_TESTS` (Module graph); the snapshot
  tests stay the Mac's.
- **Snapshot tests** pin how each state renders, in light and dark: `ImageRenderer` draws the view
  in the color scheme the test sets, and `assertSnapshot` compares it with the reference in
  `__Snapshots__` beside the test (Bazel puts them in the test's runfiles). macOS doesn't scale
  text with Dynamic Type, so the Mac pins no Dynamic Type sizes. `ImageRenderer` draws SwiftUI's
  own views; one that wraps AppKit (`NSViewRepresentable`) renders as a placeholder, so host that
  one in an `NSWindow` and snapshot the `NSHostingView`. A snapshot is worth only what a person
  reads in it, so look at every recorded image before committing it. After a change to how a view
  looks, `just record-snapshots`, then review the changed images in `git diff`.
- **Accessibility**: every control has an `accessibilityLabel`; an image that only decorates is
  `accessibilityHidden(true)`; rows that read as one item combine (`.accessibilityElement(children:
  .combine)`); animations respect `accessibilityReduceMotion`; sizes that should grow with text use
  `@ScaledMetric`, and fonts are text styles (`.title`), never fixed sizes. `just lint` runs
  a11y-check over the views.
- `just lint` (SwiftLint, `--strict`, `.swiftlint.yml` plus `.swiftlint-tests.yml` for tests) must
  pass; fix the code rather than disable a rule inline.

<!-- views:end -->
## Building blocks

The owner's own libraries, first in line under "Don't reinvent the wheel" (House rules). Reach
for them before writing a graph, a container or an operator chain by hand, and before adding a
third-party package for the same job. Add one as a row in `PACKAGES` (`scripts/modules.py`).

| Library | What it is | Use it for |
|---|---|---|
| [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) | A generic, high-performance graph library: copy-on-write representations (`AdjacencyList`, `CompressedSparseRow`, `AdjacencyMatrix`, pseudographs, stable graphs), graph classes with invariants (`DirectedAcyclicGraph`, `BipartiteGraph`, `Tree`) and algorithms (traversal, shortest paths, flows, matching, connectivity, isomorphism, layout) | Anything shaped like a graph or DAG: dependency orderings, scheduling, routing, state machines, reachability. Products are per module (`.product(name: "ShortestPaths", package: "Grafluent")`); the umbrella is `Grafluent`. |
| [GrafluentCollections](https://github.com/Tyler-Keith-Thompson/GrafluentCollections) | Graph-shaped collections as copy-on-write values with the standard library's and swift-collections' API shape: balanced search trees (`AVLTree`/`AVLDictionary`, `RedBlackTree`, `Treap`, `SplayTree`) and `FenwickTree` so far; tries, suffix structures, decision diagrams, B-trees, segment, interval and spatial trees, ropes, persistent trees and an LRU cache planned. Tree- and graph-shaped ones convert to the matching Grafluent type | Sorted sets and dictionaries that take inserts and removals, prefix and range sums with updates; check its backlog before hand-writing a planned structure. Products are per module (`.product(name: "BinarySearchTrees", package: "GrafluentCollections")`); the umbrella is `GrafluentCollections`. |
| [SwiftPRNG](https://github.com/Tyler-Keith-Thompson/SwiftPRNG) | Seeded random numbers that reproduce bit for bit on every platform and Swift release: generators as values (`Xoshiro256StarStar`, `Xoroshiro128Plus`, `SplitMix64`, with `jump()` for streams that never overlap), platform-stable draws (`uniform(in:)`, `integer(in:)`, `bernoulli(_:)`, with `checked` spellings), `SeedTree` (a seed per named decision, so adding a draw shifts nothing elsewhere, with overrides and `fitting` to search one subtree for a seed that meets a predicate) and `SeedSearch` (the smallest matching seed, concurrently) | Every seeded test, and any program whose randomness must replay: simulations, procedural generation, games, sampling. Never hand-write a generator. `Xoroshiro128Plus(seed:)` gives the same numbers as a hand-written `SeededRandomNumberGenerator` (xoroshiro128+ seeded by SplitMix64), so replacing one changes no pinned value. Products are per module (`.product(name: "Generators", package: "SwiftPRNG")`: `Generators`, `Sampling`, `SeedTrees`, `SeedDiscovery`); the umbrella is `SwiftPRNG`. |
| [DependencyInjection](https://github.com/Tyler-Keith-Thompson/DependencyInjection) | Swift 6 dependency injection: `Factory` values on `Container`, `@Injected` / `@LazyInjected` / `@ConstructorInjected`, unique, cached and shared scopes, hierarchical containers, and `withTestContainer` so concurrent tests never share state | Any seam a test needs to replace (clocks, network, storage). Tests wrap their body in `withTestContainer { }` and register doubles there. Product `DependencyInjection`. |
| [Afluent](https://github.com/Tyler-Keith-Thompson/Afluent) | Reactive operators over async/await: `DeferredTask` (a unit of work that yields one value) and `AsyncSequence` extensions with Combine's names (`map`, `flatMap`, `catch`, `retry`, `debounce`, `share`, …), plus `AfluentTesting` | Pipelines over async work where Combine would once have been used; a Combine replacement in new code. Products `Afluent` and, for test targets, `AfluentTesting`. |
| [DebugDrawer](https://github.com/Tyler-Keith-Thompson/DebugDrawer) | A plugin-based debug drawer for SwiftUI apps on iOS and macOS: a slide-in panel attached at the root view (`.debugDrawer()`), opened by `DebugDrawer.shared.toggle()`, with a library per plugin (console, performance, network, UserDefaults, app info, …) and local plugins tied to a view's lifetime (`.debugLocalPlugin(_:)`). It compiles to no-ops in release builds | Any debug-only tool an app needs (a switch, a fake response, a state dump): write a DebugDrawer plugin, installed from the composition root, instead of a one-off debug screen or gesture. Products are per plugin (`DebugDrawerConsolePlugin`, …); the core is `DebugDrawer`. | <!-- swiftui:line -->

Their conventions carry over: value types, typed errors, `checked:` spellings that throw where
the plain spelling traps, tests with Swift Testing.

## Workflow

### Adding a feature

A feature is done when it has all of these. Copy what its sibling features in the module already
have.

1. **Code and docs.** The implementation, with doc comments per "Docs" below. A new module gets a
   row in `scripts/modules.py`, then `just modules`, the README's module table and the umbrella
   DocC catalog's topic list (``` ``/Module`` ```: a link to another module needs the slash).
2. **Tests** in `Tests/<Module>Tests`:
   - hand-worked cases;
   - edge cases: empty input, one element, the boundaries of every range;
   - `checked:` spellings and their errors;
   - exit tests for every trap;
   - a property test against a naive reference (`swift-property-based`).
<!-- mutation:begin -->
   - planted bugs in `scripts/mutants/<Module>.py` for the new code, then `just mutate <Module>`:
     every mutant caught, or a note in the spec on why a survivor is equivalent. A new module
     gets a spec of its own, copied from `Greetings.py`. A simulator test target in the spec's
     `TESTS` runs through Bazel, in a copy of the workspace, for the mutants the Mac tests let
     through, so a mutant in code under `#if canImport(UIKit)` is caught there.
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
4. **A benchmark** in `Benchmarks/Benchmarks/<Module>Benchmarks` (a row in `BENCHMARKS`, then
   `just modules`) where speed matters, starting with a `BASELINE` entry: the hand-written form the code must keep pace with. Measure in
   release, and add a ratio test in `Tests/<Module>Tests/Performance/` where siblings have one.
   Use small inputs in debug builds, because the timing only runs in release.
   Judge a speed change by `just bench-simulated-compare --target <Module>Benchmarks`: its
   instruction, cache-miss and branch counts don't move when the machine is busy, as wall clock
   does. Allocation counts and absolute times still come from `just bench`, on a quiet machine.
   Re-record the `simulated` baseline for the targets a change touches
   (`just bench-simulated --target X`) and commit it with the change. Its `results.json` is
   pretty-printed with sorted keys, one benchmark's entry on lines of its own, and a benchmark
   whose instruction and malloc counts moved less than compare's 5% threshold keeps its recorded
   entry. So the file changes only where a benchmark did, and pull requests that change different
   benchmarks of one target merge without a conflict. Resolve a conflict by re-recording after
   the merge, never by hand. A benchmark whose mallocs drop to zero counts as moved. Harness
   options (`--iterations`, `--filter`) measure uncached and write the same format, keeping the
   entries that didn't move. To rewrite every entry (a change aimed at cache misses alone), delete
   the file first.
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
| A module in `FIRMWARE_MODULES`, or `Firmware/` | `just firmware` (needs ESP-IDF; say so when it isn't installed) <!-- embedded:line --> |
| `Sources/ProjectNameMCP`, or anything that writes to standard output | `just install`, then `claude mcp list` shows it connected <!-- mcp:line --> |
| A view, or anything a view draws with | `just test` (lint, view and snapshot tests); `just record-snapshots` if it should look different, then review the images <!-- app:line --> |
| `tools/iphone/`, signing, or the phone recipes | `bazel test //tools/iphone:iphone_test`, then `just phone-install` on a connected iPhone <!-- app:line --> |
| `Apps/`, or how screens connect | `just smoke` <!-- app:line -->
| A view module, or anything a view draws with | `just test` (lint, view and snapshot tests); `just record-snapshots` if it should look different, then review the images; `just spm-test` <!-- views:line --> |
| Integer arithmetic that could overflow, or anything platform-conditional | `just wasi-test -c release --targets XTests` (a 32-bit `Int`) <!-- wasm:line --> |
| `Benchmarks/`, or an API the benchmarks call | `cd Benchmarks && env -u TOOLCHAINS xcrun --toolchain default swift build -c release` <!-- benchmarks:line --> |
| `Examples/`, or an API the examples call | `just examples-test`, then each `just example-*` the change touches (`just examples` for all) <!-- examples:line --> |
| A change meant to be faster | `just bench-simulated-compare --target <Module>Benchmarks`, not `just bench-compare` <!-- benchmarks:line --> |

### Pushing

<!-- !trunk:begin -->
Push finished work to `main` yourself; don't wait to be asked, and never end a task with
<!-- !trunk:end -->
<!-- ci:begin -->
<!-- !trunk:begin -->
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
<!-- !trunk:end -->
<!-- trunk:begin -->
Ship finished work yourself; don't wait to be asked, and never end a task with finished work
unmerged. `main` takes changes only through Trunk's merge queue, and every merge releases a patch
version, so ship once per batch: when the work the owner gave you is done (the whole request, or
Ready is empty when working the backlog), put everything it produced on one branch.
<!-- fly:begin -->
Every merge also deploys to Fly.io.
<!-- fly:end -->

1. Verify the committed state in a clean worktree: `bazel test //...` in debug, then
   `--config=release`.
2. Push the branch, open a pull request (`gh pr create`) and queue it with a `/trunk merge`
   comment (`gh pr comment --body "/trunk merge"`). Trunk tests it on a `trunk-merge/` branch
   against the current `main` and merges it once the checks `.trunk/trunk.yaml` names pass.
3. Watch it merge (`gh pr view --json state`), then the Release and DocC workflows to green, and
   fix anything that breaks in a new pull request.
4. Don't add CI steps that rebuild without the owner's approval. A job that must pass before a
   merge goes in `.trunk/trunk.yaml`'s `required_statuses` by its name, and in branch
   protection's required checks.
<!-- trunk:end -->
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
- Small files, one main type each. Vocabulary a body needs goes in a `fileprivate` extension on
  the type it describes (`extension User { fileprivate func matches(_ term: String) -> Bool }`),
  so the body reads as a sentence.
- No hooks or SPI added only for tests.
- Underscored Swift features (`@_spi`, `_modify`, `@_effects`, `@_exported`) are fine where they
  help. Apple private API is not: undocumented framework symbols, private selectors, private
  frameworks, anything App Review rejects.

### Seams and composition (*default*)

How code that reaches past the process is split: networks, disks, clocks, other services. A pure
library with none of that can skip this section.

- **Layers with one job each.** A transport (HTTP, a file) knows nothing of the domain. A service
  built on it speaks one API. Persistence and features build on services. A module depends only
  on layers below it. Where two modules' models meet, an adapter in the module that imports both
  translates between them, rather than one importing the other. A few lines duplicated across
  modules cost less than coupling them; say so in a comment where it happens.
- **A protocol at every seam.** Anything a test must replace is a protocol marked `@Mockable`.
  Its production conformer is internal and takes the protocol's name with a leading underscore
  (`_SearchService`), so autocomplete offers the protocol. Beside it, a `Factory` on `Container`
  (DependencyInjection) returns it as the protocol, scoped on purpose: `.cached` for one instance
  that holds state, `.shared` for one instance while anyone holds it, unique otherwise. Callers
  resolve it with `@Injected`, `@LazyInjected` or `@ConstructorInjected`, never by naming the
  conformer.
- **The executable is the composition root.** Modules ship working defaults (an in-memory store);
  the executable registers what production swaps in (the store on disk) at startup.
- **Async work is a pipeline of values.** With Afluent, a call returns a lazy unit of work
  (`DeferredTask`, `AsynchronousUnitOfWork`) built from operators: `flatMap` to the next step,
  `tryMap` to validate, `decode`, `handleEvents` for side effects (caching, logging), `tryCatch`
  for a fallback, `shareFromCache` so simultaneous identical requests make one call. Nothing runs
  until `execute()`, so callers compose, retry and cancel it freely.
- **Time is a dependency.** Code that waits, debounces or times out takes a clock registered on
  `Container` (`AnyClock<Duration>`), never an inline `Task.sleep` or `ContinuousClock()`. Tests
  register a `TestClock` (swift-clocks) and advance it.
- **State is an enum of what can be true.** A screen, a response or a load is an enum with a case
  per state (`prompt`, `loading`, `results([User])`, `noResults(String)`, `failed`), mapped once
  from the outcome, not optionals and flags that can disagree.
- **Isolation states its reason.** Mutable state reached from async callers lives in an actor, or
  behind `Mutex` where the hops would cost too much; a comment says which and when to switch.
- **Literals checked at compile time.** A literal URL is `#URL("…")` (the URL macro), not
  `URL(string:)!`. A force unwrap or trap that remains has a comment proving it can't fire and
  why a crash beats a thrown error no caller could handle.
- **Logging.** A type that logs has one `private static let logger`: swift-log's
  `Logger(label: "<module>.<Type>")`, or `os.Logger(subsystem:category:)` in Apple-only code, where
  every interpolation of user data stays private. Levels mean something: `debug` for a path taken,
  `info` for a notable event, `notice` for a degraded result (cached data served), `error` for a
  failure. Cancellation is not a failure; don't log it as one. Logs are for developers; tests
  don't pin them.

### Tests (*default*)

- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`). Never XCTest.
- Each test is self-contained and portable: no assertion or setup helpers, not DRY; a test
  copied to another file still works. Shared fixture data in `ProjectNameTestSupport` is tolerated;
  shared assertions are not.
- Test names state the rule they pin ("The checked spelling throws EmptyName for an empty name").
- **Sociable.** A test runs the real code under test and its real collaborators wherever they are
  fast and deterministic, and mocks only the seams that reach out (network, disk, clock) or that
  it must steer. Inside `withTestContainer { }`, `Container.x.useProduction()` resolves the real
  subject; its seams get mocks.
- **Shape.** Arrange; then act on `sut`; then assert, with a blank line between. Name the values
  `expected…` and `actual`. Where the call itself is the rule, `verify(mock)` pins it:
  `.called(.once)`, or `.called(.never)` for one that must not happen.
- **Deterministic concurrency.** Never sleep to let something happen. Order concurrent work with
  gates the test opens (a stub that awaits a `SingleValueSubject` the test sends), advance a
  `TestClock`, and run main-actor tests under `withMainSerialExecutor` (swift-concurrency-extras).
  A suite that awaits carries `.timeLimit(.minutes(1))`, so a hang fails rather than stalls.
- **Unhappy paths.** Every failure a seam can produce (a timeout, no network, a malformed
  response, a missing resource) has a test of what the caller sees.
- Tests may call underscored and `package` API.
- Test doubles come from [Mockable](https://github.com/Kolos65/Mockable): mark the protocol at the
  seam `@Mockable` and use the generated `Mock<Protocol>` with `given`, `when` and `verify`
  inside the test, rather than hand-writing doubles. With DependencyInjection, register the mock
  inside the test's `withTestContainer { }`. Mocks exist only in debug builds, so a
  `PerformanceTests` target never uses one.
- Property tests use swift-property-based (`import PropertyBased`, `propertyCheck`).
- Randomized tests are seeded so a failure reproduces from its seed alone: a SwiftPRNG generator
  (`Xoshiro256StarStar(seed:)`), drawn through its platform-stable `uniform(in:)`, `integer(in:)`
  and `bernoulli(_:)` rather than the standard library's `random(in:using:)`, whose answers may
  change between Swift releases.

### Docs (*default*)

- Describe the current API. No history ("previously", "renamed"), design debates, comparisons
  with other libraries, or benchmark numbers in doc comments or READMEs. Complexity bounds are
  fine.
- Doc comments: a one-line summary, then parameters, return value, complexity, and what traps or
  throws.
- `//` comments say why, where the code makes a choice a reader would question: the data
  structure, an actor over a `Mutex`, deliberate duplication, a force unwrap, the package rejected
  and when it would become the right one. Doc comments describe the API; these record decisions. A
  comment that restates the code is deleted.
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
