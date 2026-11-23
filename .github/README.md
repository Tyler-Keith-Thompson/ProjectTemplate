# ProjectTemplate

A starting point for Swift projects. One command creates a Swift library, a Vapor server, ESP32
firmware in Embedded Swift or an MCP server that already builds, tests, documents itself and
releases on every push. Servers also ship a Docker image and can deploy to Fly.io; firmware builds
and flashes through ESP-IDF; an MCP server installs for Claude Code. When the template improves, the projects made from it pull
the change in with `just template-update`.

```sh
git clone https://github.com/Tyler-Keith-Thompson/ProjectTemplate ~/workspace/ProjectTemplate
~/workspace/ProjectTemplate/bootstrap.sh MyThing
```

That asks a few questions, writes `~/workspace/MyThing`, resolves its dependencies and runs its
tests. The project is ordinary code from then on: nothing in it depends on the template at run or
build time.

## What a new project has

- **Two build systems from one table.** Bazel for development (fast incremental builds, a remote
  cache, an Xcode project generated from the graph); SwiftPM for publishing. `scripts/modules.py`
  lists the modules, their dependencies and test targets, and writes `Package.swift` and every
  `BUILD.bazel`; a test fails if the two disagree.
- **A justfile over the top.** `just test`, `just docs`, `just generate`, `just bench`: one
  vocabulary in every project.
- **A remote cache with no setup per project.** Store a BuildBuddy API key in the Keychain once
  (`just buildbuddy-key`) and every project's builds use BuildBuddy's cache and build results;
  `just ci-secrets` gives a repository's CI the same key with `gh`. The key is never written to
  a file.
- **Strict defaults.** Swift 6 language mode, first-party warnings as errors, a debug and a release
  configuration that don't throw away each other's cache.
- **Tests with Swift Testing**, including an example module (`Greetings`) that shows the house
  style: hand-worked cases, edge cases, exit tests for traps, a property test against a naive
  reference, a seeded random number generator for reproducible failures.
- **DocC** for every module, merged into one site and published to GitHub Pages.
- **CI on GitHub Actions**: tests on every branch and pull request; every push to `main` that
  passes is tagged and released as the next patch version.
- **Agent instructions.** `AGENTS.md` (which `CLAUDE.md` includes) tells a coding agent the
  layout, the commands, the feature checklist and the house rules, so agents build the project the
  way a person would.
- **Mutation testing** (optional): planted bugs per module, compiled into one build behind
  runtime switches, and a report of any the tests let through.
- **Fuzzing** (optional): a libFuzzer target per module in a separate package, checking the
  code against a simple model, with a local corpus each run resumes from.
- **Differential testing** (optional): seeded random cases answered by the library and by pinned
  reference implementations run through `uv`, with every disagreement saved to reproduce.
- **WebAssembly tests** (optional, libraries): the test suites built for wasm32-wasi and run under
  wasmtime, where `Int` is 32 bits.
- **A browser explorer** (optional, libraries): pages that run the library as WebAssembly, with
  the code each runs beside it, published next to the docs.
- **SwiftUI views** (optional, libraries): a view module for macOS and iOS with ViewInspector view
  tests, snapshot tests on the Mac, and SwiftLint and a11y-check (`just lint`).
- **Benchmarks** (optional): a separate package on
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

## Requirements

macOS with Xcode's Swift 6.3 toolchain, and from Homebrew: `bazelisk`, `just`. Benchmarks need
`jemalloc`; servers need Docker and, for the load test, `k6`; Fly.io deployment needs `flyctl`;
`just ci-secrets` needs `gh`, signed in. Fuzzing needs `swiftly` with a swift.org toolchain
(`swiftly install 6.3.3`), since Xcode's has no libFuzzer runtime. Differential testing needs
`uv`. WebAssembly tests need swiftly's toolchain, its Swift SDK for WebAssembly and `wasmtime`; the
explorer needs the same toolchain and SDK, and `binaryen` for `wasm-opt`. Firmware needs swiftly's
Swift 6.3.3 (`swiftly install 6.3.3`), since Xcode's toolchain has no Embedded Swift for RISC-V, and
[ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/get-started/) 5.5 in
`~/esp/esp-idf` or `IDF_PATH`, for building the image. An app needs an iOS 18 simulator runtime in
Xcode (the device and runtime `.bazelrc` names).

## Starting a project

```sh
./bootstrap.sh MyThing                                   # asks for the type and options
./bootstrap.sh MyThing ~/somewhere/MyThing               # another destination
./bootstrap.sh --library --benchmarks MyLibrary          # a library with benchmarks
./bootstrap.sh --library --views MyViews                 # a library of SwiftUI views
./bootstrap.sh --server --fly --database MyService       # a server on Fly.io with SQLite
./bootstrap.sh --server --yes MyService                  # a server, nothing optional, no prompts
./bootstrap.sh --embedded --wasm MyGadget                # ESP32 firmware, its tests also on a 32-bit Int
./bootstrap.sh --mcp MyTools                             # an MCP server for Claude Code
./bootstrap.sh --app MyApp                               # an iOS app in SwiftUI
```

The name must be an UpperCamelCase Swift module name. The destination defaults to
`~/workspace/<Name>`. Run from a terminal, the script asks for the type and every option not given
as a flag; otherwise (or with `--yes`) those default to off. It copies the template, renames
`ProjectName`/`projectname` to the new name, keeps or drops the optional sections, stamps the
project with `.template.json`, runs `just modules`, `git init`, `just resolve` and `just test`,
then prints what to fill in.

### Types

| Type | What it adds |
|---|---|
| `library` (default) | Nothing: the template as it stands. A Swift package published through SwiftPM, with README examples as tests (`Tests/ProjectNameTests`). |
| `server` | `templates/server/` on top: a Vapor `App` module (`configure(_:)`, routes), a `ProjectNameServer` executable, `AppTests` (VaporTesting), a Dockerfile building with SwiftPM pinned by `swift/Package.resolved`, `just run`, `just docker`, and a k6 load test (`LoadTests/load.js`, `just load`) against a fresh production image. Platforms narrow to macOS; the README's installation section and README tests are dropped. |
| `mcp` | `templates/mcp/` on top: a `Tools` module on the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (`ToolServer`; `ToolHandler`, whose work takes `Decodable` arguments and returns or throws `Encodable` values, sent as structured content and as JSON text; an example `greet` tool), `ToolsTests` against a real client over `InMemoryTransport`, a `ProjectNameMCP` executable (swift-argument-parser) serving them on `StdioTransport`, `just run`, and `just install` into `~/.local/bin/projectname-mcp`. Platforms narrow to macOS; the README's installation section and README tests are dropped, and the README says how to register the server with `claude mcp add`. |
| `app` | `templates/app/` on top: an iOS app in SwiftUI (`Apps/ProjectName`, an `ios_application` holding only the composition root), a `GreetingService` module (a `@Mockable` protocol, `_GreetingService`, a `Container` factory) tested on the Mac, and two iOS modules (`IOS_MODULES` in `scripts/modules.py`), `DesignSystem` and `GreetingFeature`, which Bazel builds for the simulator and Package.swift leaves out. `GreetingFeatureTests` runs in the simulator: ViewInspector tests with a `TestClock` under `withMainSerialExecutor`, and snapshot tests through `tools/snapshots` (references in `__Snapshots__`, packaged into the bundle; `just record-snapshots`). DebugDrawer attached at the root view, opened on Control-D or a shake in debug builds and compiled to no-ops in release (`Apps/ProjectName/DebugDrawerTrigger.swift`). An XCUITest smoke test (`just smoke`), `just run`, and `just lint` (`tools/lint.bzl`: SwiftLint with `.swiftlint.yml`, and a11y-check), which `just test` runs first. No CI (`--ci` and `--trunk` are refused); the README's installation section and README tests are dropped. |
| `embedded` | `templates/embedded/` on top: `Firmware/`, an ESP-IDF project for the ESP32-C6 whose app (`Firmware/main`) is Embedded Swift; `tools/embedded.bzl`, which compiles every module in `FIRMWARE_MODULES` (`scripts/modules.py`) as Embedded Swift for the chip beside its host library (`//Sources/X:XEmbedded`, built by `bazel build //...`) and gathers them as `//Firmware:Modules`; and `tools/embedded-swift`, the one swift.org toolchain both builds use. `just firmware`, `just flash`, `just monitor`, `just menuconfig`, `just firmware-size`. Platforms narrow to macOS; the README's installation section and README tests are dropped. |

### Options

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
| `--fly` (server) | `fly.toml` (suspend when idle, `/health` checks), a `deploy` job in `Release.yml` after CI (`FLY_API_TOKEN` secret), `just deploy`. Without it nothing deploys. |
| `--database` (server) | Fluent with SQLite in WAL mode: the file at `DATABASE_PATH`, memory when unset (production refuses to start without it); an example model and migration; a volume mount in `fly.toml`. |
| `--fly --database` | Litestream: `litestream.yml` replicates to Backblaze B2 (the `B2_*` Fly secrets), and `scripts/docker-entrypoint.sh` restores the database onto an empty volume, then runs the server under `litestream replicate`. Without the secrets it serves unreplicated. With one machine and one volume, Litestream runs directly, without LiteFS. |
| `--no-ci` | Leaves out `.github/workflows/` (CI, PR CI, Release, DocC; `templates/ci/` here) and everything that leans on it: `just ci-secrets`, the documentation link, the release and push rules in AGENTS.md. With `--fly`, `just deploy` is the only deploy; with `--explore`, `just explore` builds the site locally and nothing publishes it. CI is the one option on by default, and the only question asked as [Y/n]. |
| `--trunk` (with CI) | `.trunk/trunk.yaml`: pull requests merge through [Trunk's merge queue](https://docs.trunk.io/merge-queue), which waits for the checks it names (`Bazel tests` and `SwiftPM tests`, which CI runs on Trunk's `trunk-merge/` branches as on every branch but `main`). AGENTS.md's push rules become: a branch, a pull request, a `/trunk merge` comment. Install Trunk's GitHub app and turn the queue on for `main`; branch protection should require `ci / Bazel tests` and `ci / SwiftPM tests`. |

## Keeping projects current

The template is versioned by its git commits (each push to `main` is also tagged). Every project
`bootstrap.sh` makes carries `.template.json`: the commit it came from, its name and its options.
`template.py` uses it to carry later template changes into the project.

```sh
just template-update                           # inside a project
./template.py update ~/workspace/MyProject     # the same, from the template
./template.py status                           # every project in ~/workspace and how far behind it is
./template.py add ~/workspace/MyProject --wasm # turn an option on in a project made without it
./template.py remove ~/workspace/MyProject --wasm  # turn it off again
./template.py retype ~/workspace/MyProject --type mcp  # change its type: a library that became an MCP server
```

`update` renders the template at the stamped commit and at `HEAD` (`bootstrap.sh --render-only`,
with the project's name and options), then takes each file that changed between the two:

| The file | Becomes |
|---|---|
| Unchanged in the project | The template's new version |
| Changed in the project too | A three-way merge (`git merge-file`); conflicts are left marked |
| Added by the template | Added, or merged when the project already has one |
| Removed by the template | Removed if unchanged in the project; otherwise kept and reported |
| Removed by the project | Left out and reported |
| Generated by `scripts/modules.py` | Regenerated by running it, not merged |

It needs a clean worktree, never commits, and moves the stamp to the new commit, so `git diff`
shows the whole update. Then resolve any conflicts, `just modules`, `just test`, and commit.
A table or function the template adds to `scripts/modules.py` (`MACROS = []`, say) merges in
without markers when the project already defines it elsewhere in the file. `just modules` refuses a
name defined twice, so the report lists it among the conflicts: keep one definition, holding the
project's rows, and delete the other.
Projects find the template at `~/workspace/ProjectTemplate`, or `$PROJECT_TEMPLATE`.

The Swift a project builds with is declared once, `SWIFT` and `SWIFT_TOOLCHAIN` in
`scripts/modules.py`. `just modules` writes them into the generated manifests and replaces the
previous ones in every other file that names them (`SWIFT_SITES`: the hand-written manifests, the
workflows, the Dockerfile, the scripts and the docs), reading the previous ones from the generated
`tools/swift_version.bzl`. When a project declares versions other than the stamped commit's,
`update`, `add` and `retype` give both renders the project's versions before merging, so those lines
never conflict, and the report says when the template's own floor has passed the project's. To
raise the template's floor, change the two lines here, `just modules`, and publish the CI images
(`ci-image/build.sh`).

Every project's Bazel builds share one disk cache, `~/.cache/bazel-disk`, which Bazel keeps under
30 GB. Projects made before that each had their own, `~/.cache/bazel-<name>`, which nothing trims;
once every project is updated past it, delete those directories by hand (`template-update` only
changes files in the project).

`add` turns options on later (`--wasm`, `--explore`, `--fuzz`, any of `bootstrap.sh`'s options for
the project's type). It renders the template at the stamped commit twice, with the project's
options and with the new ones too, and merges every file that differs the same way, so the result
matches a project made with those options from the start. It refuses an option the stamped commit
doesn't know yet (run `update` first) or one that doesn't fit the project's type, needs a clean
worktree, records the options in the stamp, and never commits.

`remove` is its mirror: it renders the stamped commit with the project's options and with the
named ones off, and merges the difference the same way, so what an option brought goes where the
project left it alone, a file the project changed is kept and reported, and files the project
added itself stay. It refuses an option the stamp doesn't have on, and `--ci` while `--trunk`
stays on; it needs a clean worktree, records the options off in the stamp, and never commits.
Removing `--wasm` from a project with `--explore` keeps `NON_WASI_PACKAGES`, which the explorer's
WebAssembly build still needs.

A project made before stamps existed is adopted with `./template.py stamp <project> --type …
[--benchmarks] [--fly] [--database]`, which records that it matches the template's `HEAD`. Later
updates merge only what changes after that. To see how far it had drifted first, render the
template with its options (`./bootstrap.sh --render-only --type … <Name> <scratch directory>`) and
compare with `git diff --no-index`.

## Working on the template

The template is itself a working library project under the placeholder name `ProjectName`: the
root `README.md`, `AGENTS.md` and the rest are what every new project starts with. This file
(`.github/README.md`, which GitHub shows in place of the root one), `bootstrap.sh`, `template.py`
and `templates/` stay behind.

### Optional pieces

Every optional piece (`benchmarks`, `mutation`, `fuzz`, `differential`, `wasm`, `explore`, `views`, `examples`, `library`, `server`, `embedded`, `mcp`, `app`, `fly`, `database`, `litestream`, `swiftui`, `wasi`, `ci`, `trunk`) keeps
or drops the sections marked for it, in any text file. `litestream` is on with `fly` and `database`
together, `swiftui` with `app` or `views` (the lint stack and view-test packages they share), and
`wasi` with `wasm` or `explore`: what any build for wasm32-wasi needs, `NON_WASI_PACKAGES` and its
manifest condition, so a render without either names neither WASI nor wasm.

- `# feature:begin` / `# feature:end` blocks (`//` in Swift and JavaScript, `<!-- -->` in
  Markdown); blocks nest, and `!feature:begin` / `!feature:end` marks a block kept when the
  feature is off;
- single lines ending in `# feature:line` or holding `<!-- feature:line -->` (table rows carry it
  inside their last cell, so the table still renders); a line may carry several, and is kept
  when all of them hold (`<!-- explore:line --><!-- !ci:line -->`);
- dormant lines, `#| code` or `//| code`, inside a block or on a marked line: comments in the
  template, uncommented when kept. They are how `scripts/modules.py`, `MODULE.bazel` and the
  release workflow's deploy job carry server and Fly.io content without the template building or
  running it in place.

The markers are removed either way. Whole files that belong to one piece are listed in
`bootstrap.sh` (`remove_unless`). When adding anything optional to the template, mark it the same
way. Keep a numbered-list item that gets marked last in its list, so removing it leaves the
numbering intact.

### Where things are

| Piece | Where | Notes |
|---|---|---|
| One module table | `scripts/modules.py` | Writes `Package.swift`, every `BUILD.bazel`, the umbrella, `swift/Package.swift`; `//:package_swift_test` keeps them honest (targets, dependencies, resources, library products) |
| Swift version | `SWIFT`, `SWIFT_TOOLCHAIN` in `scripts/modules.py` | Generated into the manifests and replaced in `SWIFT_SITES` from the record in `tools/swift_version.bzl`; `template.py` renders with the project's versions |
| Warnings as errors | `tools/swift_rules.bzl` | First-party only; dependencies build quietly (`.bazelrc`) |
| Swift 6 mode, one package name | `tools/swift_rules.bzl` | So `package` access and retroactive conformances agree with SwiftPM |
| Debug default, release config | `.bazelrc`, `justfile` | Release uses its own output base; `debug-only` tags keep ordinary tests out of release |
| Analysis-cache guardrail | `.bazelrc` | `--noallow_analysis_cache_discard` |
| Remote cache | `tools/bazel`, `tools/buildbuddy.bazelrc`, `tools/buildbuddy-credentials`, CI | BuildBuddy, on when the login Keychain holds the key: Bazelisk runs `tools/bazel`, which adds the BuildBuddy rc file, and a credential helper hands Bazel the key per request. Large outputs move in content-defined chunks (`--experimental_remote_cache_chunking`). CI writes the same flags from the `BUILDBUDDY_API_KEY` secret (`just ci-secrets`). `user.bazelrc.example` is the manual setup for a machine without a Keychain. |
| CI image | `ci-image/`, CI | `ghcr.io/tyler-keith-thompson/swift-bazel:<swift>-<bazel>`: the `swift` image with Bazelisk and the Bazel in `.bazelversion` already downloaded, so CI's Bazel jobs install nothing. The package is private: each project's repository gets Read under Manage Actions access in its settings, and the jobs pull with their `GITHUB_TOKEN` (`packages: read`). `ci-image/build.sh --push [<swift>...]` builds it for arm64 and amd64 and pushes it (gh needs `write:packages`): `SWIFT` and `SWIFT_TOOLCHAIN` (`scripts/modules.py`) for the template's workflows by default, and the higher versions in its `swift_versions` list for projects that raise their floor (add one there first); run it after changing `.bazelversion` or the template's Swift version. `just modules` writes the tags into the workflows. Bootstrap leaves the directory out of projects. Bazel's downloads persist between runs in `actions/cache` (`~/.cache/bazel-repository`, keyed on `MODULE.bazel.lock` and `swift/Package.resolved`). |
| Xcode project from the graph | `just generate` | rules_xcodeproj, into `xcode/`; schemes derived from `Tests/*` |
| DocC site | `tools/docc.bzl`, `just docs`, `docc.yml` | One archive per module, merged; published to gh-pages |
| Benchmarks (opt-in) | `Benchmarks/`, `tools/benchmarks.bzl`, `scripts/bench_simulated.py` | Separate package, ordo-one/benchmark, generated from `BENCHMARKS` in `scripts/modules.py`; `BASELINE` entries, committed `main` and `simulated` baselines. Simulated counts are cached Bazel outputs, one `no-sandbox` action per target, so only targets whose inputs changed are measured |
| Mutation testing (opt-in) | `scripts/mutate.py`, `scripts/mutants/` | Mutant schemata over a scratch SwiftPM copy outside the repository (`~/Library/Caches/<project>-mutation`); `<PROJECT>_MUTANT` picks the live mutant. A spec's simulator test targets run through Bazel in a second copy there, the whole checkout with the schemata applied: one build, then a `bazel test` per mutant the Mac tests let through, the variable passed on through an `env_inherit` the copy adds to each `ios_unit_test`; the copy's Bazel server is shut down at the end |
| Fuzzing (opt-in) | `Fuzz/`, `scripts/fuzz.py` | libFuzzer through `LLVMFuzzerRunDriver` (each target's `@main` calls `runFuzzer`); swiftly's toolchain, `<PROJECT>_FUZZ_SWIFT` picks its version; corpus in `Fuzz/Corpus/`, crashes in `Fuzz/Crashes/` |
| Differential testing (opt-in) | `Differential/`, `scripts/differential*.py` | `DIFFERENTIAL_DEPENDENCIES` in `scripts/modules.py` writes the package's BUILD.bazel and Package.swift; areas are discovered by file name |
| WebAssembly tests (opt-in) | `scripts/wasi_test.py`, `scripts/modules.py` | The generated `Package.swift` reads `<PROJECT>_WASI_TESTS` (marked `wasm` in the generator); builds in `.build/wasm`. `NON_WASI_PACKAGES` (marked `wasi`: with `--wasm` or `--explore`, any type that takes them) links a package's products on every platform but WASI |
| Browser explorer (opt-in) | `Explore/`, `docc.yml` | ElementaryUI and JavaScriptKit (PackageToJS); the workflow job is dormant (`#|`) in the template, so only `--explore` projects run it |
| Mocks (off until needed) | `scripts/modules.py` (`MOCKING`), `tools/BUILD.bazel` | Mockable row commented out in `PACKAGES`; a module depending on it gets `MOCKING` in debug only, in both build systems |
| CI | `templates/ci/.github/workflows` (copied into projects with CI; the template repository runs no workflows) | Linux arm64 Bazel tests on branches and PRs; tag-and-release on main |
| Test support | `Tests/ProjectNameTestSupport` | Tags and shared fixtures; data only |
| Executables | `EXECUTABLES` in `scripts/modules.py` | `.executableTarget` in SwiftPM, `swift_binary` in Bazel, a run scheme in Xcode; left out of the umbrella and the docs |
| Example modules | `EXAMPLE_MODULES` in `scripts/modules.py` | Targets in both build systems with no library product, umbrella import or DocC archive; `tools/examples.bzl` (generated) tells the root BUILD which packages to leave out of the docs; only executables, tests and other examples may depend on one |
| Modules outside the umbrella | `NON_UMBRELLA_MODULES` in `scripts/modules.py` | A library product and DocC archive like any module, but no `@_exported import` in the generated umbrella, for a module adopters import on purpose (a test-support back end); `//:package_swift_test` also checks the manifest's library products against the Bazel graph |
| Modules that import Testing | `TESTING_MODULES` in `scripts/modules.py`, `tools/docc.bzl` | Empty until a project adds one. A shipped test helper (a `Trait`, an assertion recording an `Issue`) gets `always_include_developer_search_paths` on its `swift_library` and its `docc_archive`, since rules_swift puts Testing on the developer search paths of testonly targets alone. `check()` refuses a name not in `MODULES`, an iOS or firmware module, one the umbrella imports, a module depending on one without being listed, and an executable depending on one. Checked on a scratch render with a sample row, since the template ships none |
| Module resources | `RESOURCES` in `scripts/modules.py`, `tools/resources.bzl`, `tools/ResourceBundleInfo.plist` | Empty until a project adds one. A module's `(rule, path)` entries, the rule `"process"` or `"copy"`, become `resources:` in Package.swift and, in Bazel, `module_resources`: `<Project>_<Module>.bundle` laid out as SwiftPM lays it out, in the runfiles of whatever links the module (macOS and Linux), an `apple_resource_bundle` of the same name and contents that rules_apple nests in an app or test bundle, and a generated `Bundle.module` that looks in both. The runfiles target offers no files of its own, since rules_apple would copy a `swift_library`'s `data` files into the bundle's root, and the macro exports the resource files for checks that compare a bundle with its sources. `check()` refuses an unknown module, a firmware module, a path that doesn't exist or leaves the module, a path listed twice or inside another, and a module holding a `PrivacyInfo.xcprivacy` that it doesn't list. `//:package_swift_test` compares each target's `resources:` entries, rule and path, with those of the `module_resources` target in the module's `data`, so a manifest that lost one fails there rather than in `Bundle.module` at run time. The benchmarks' staging copies a module's resources with its sources; `just wasi-test` maps the checkout at its own path, where SwiftPM's `Bundle.module` looks. Checked on scratch renders with sample rows, since the template ships none |
| Simulator tests beside the Mac's | `SIMULATOR_TESTS` in `scripts/modules.py` | Empty until a project adds one. A listed test target keeps its Package.swift target, swift_test and Xcode bundle, and gains `<Target>Simulator`, an `ios_unit_test` hosted by `tools/test_host` (tagged `manual`, so Linux never builds it), incompatible off macOS, of `<Target>SimulatorLibrary`: the same sources built for iOS alone, with Apple-only products listed plainly and without the Mac library's `data`, which rules_apple would flatten into the bundle as resources. `check()` refuses an unknown target, one that runs in the simulator alone already (an iOS module or a `//` label among its dependencies), and the table without `tools/test_host` and `.bazelrc`'s `--local_resources=simulator`, which only the app type ships. The Mac half must run at least one test (rules_swift's runner fails a run of none). Checked on scratch app and `--views` renders with a sample row, since the template ships none |
| Macros | `MACROS` in `scripts/modules.py`, `tools/swift_rules.bzl`, `tools/compile_failure_test.bzl` | Empty until a project adds one. A row is a compiler plugin: a `.macro` target in Package.swift and a `swift_compiler_plugin` in Bazel, in the `plugins` of each module that lists it; a test target that lists it links `<Plugin>Library`, its sources compiled as a library in the test's package with the entry point renamed. No product, docs or umbrella import (`tools/macros.bzl`, generated, tells the root BUILD). `//:package_swift_test`, the benchmarks' source aspect and `scripts/mutate.py` follow plugins as dependencies. `swift_compile_failure_test` type-checks a fixture in `Tests/CompileFailures` (left out of the test bundles by name) with the plugin loaded and passes when the expected errors appear. Checked on a scratch render with a sample row, since the template ships none |
| Command plugins | `PLUGINS` in `scripts/modules.py`, `Plugins/<name>/` | Empty until a project adds one. A row (name, verb, description, reason) is a `.plugin` target and product in Package.swift, run with `swift package <verb>`; a reason asks for `.writeToPackageDirectory`, `None` for no permissions. Bazel builds none of it: no BUILD.bazel in `Plugins/`, and `//:package_swift_test` and `//:docs` read only `Sources/` and `Tests/`. `check()` refuses a duplicate name or verb, a name taken by a module, macro, executable or test target, and a plugin with no Swift sources. `scripts/mutate.py` leaves plugins out of its pruned manifest, the benchmarks stage a placeholder source for each, and the server image's context lets `Plugins/` in. Checked on a scratch render with a sample row, since the template ships none |
| Server type | `templates/server/` | Vapor, Docker, a k6 load test, optionally Fly.io, SQLite and Litestream |
| MCP type | `templates/mcp/` | `Tools` (`ToolServer`, `ToolHandler`), the stdio executable, `just install` |
| App type | `templates/app/`, `IOS_MODULES` in `scripts/modules.py` | iOS modules get `target_compatible_with` iOS and no docs; Package.swift declares only the packages its own targets use; a test target depending on one becomes an `ios_unit_test` hosted by `tools/test_host` (a logic test can't give a window a scene) on rules_apple's default runner, which drives `xcodebuild`, with a `Snapshots` resource bundle; `tools/ios.bzl` (generated) tells the root BUILD which packages to leave out of the docs and `//:package_swift_test`. Lint is an aspect (`tools/lint.bzl`) over `swift_library` targets with no external workspace |
| Views option | `templates/views/`, `APPLE_ONLY_PACKAGES` and `APPLE_ONLY_TESTS` in `scripts/modules.py` | A library's SwiftUI modules: `#if canImport(SwiftUI)` sources, tests on the Mac under `#if os(macOS)`; a test target on SnapshotTesting gets `__Snapshots__` as `data` (Bazel) and excluded (SwiftPM). Lint (`tools/lint.bzl`, `third_party/`, `.swiftlint*.yml`) is shared with the app type, marked `swiftui` |
| Embedded type | `templates/embedded/`, `FIRMWARE_MODULES` in `scripts/modules.py` | `embedded_swift_module` per firmware module and `embedded_swift_firmware` (`tools/embedded.bzl`); the ESP-IDF build runs Bazel before compiling the app, checks the modules' architecture against the chip's, and keeps the GOT that Swift's position-independent code needs (`Firmware/main/swift.lf`) |
| Example module | `Sources/Greetings`, `Tests/GreetingsTests` | The house style: composable value type, plain/checked spellings, hand-worked, edge, exit and property tests |
| Agent instructions | `AGENTS.md` (`CLAUDE.md` includes it) | Layout, commands, building blocks, feature checklist, house rules, API conventions |
| Claude permissions | `.claude/settings.json` | `just`, `bazel build/test/query`, read-only git |


### Checking a change

The template repository runs no CI, so these local checks are all that stands behind a push.
Validate the template in place after editing: `just modules && just test && just spm-test &&
just docs`. After touching a marked section, bootstrap each variant it affects into a scratch
directory with `--yes` and check them: `--library` with and without `--benchmarks`, `--mutation`, `--fuzz`, `--differential`, `--wasm` and `--explore`; `--server`
alone, with `--database`, and with `--fly --database`; `--embedded` alone and with `--wasm`; `--mcp`; `--app` alone and with `--benchmarks --mutation`; `--library --views`. For a server change, also run `just spm`
and `just load` in the bootstrapped project; for a fuzz change, `just fuzz -t 30` and
`just fuzz-regress`; for a differential change, `just diff`; for a WebAssembly change, `just wasi-test`; for an explorer change, `just explore`; for an
embedded change, `just firmware` in the bootstrapped project; for an MCP change, `INSTALL_DIR=<scratch> just install`
and an `initialize`, `tools/list` and `tools/call` piped into the installed binary; for an app change,
`just lint`, `just smoke` and, after a change to how a screen looks, `just record-snapshots` with the images reviewed; for a views change, `just spm-test` and, after a change to how a view looks, `just record-snapshots` with the images reviewed, then the references copied back into `templates/views`. For a change to
how macros build (`MACROS`, `tools/compile_failure_test.bzl`, what follows `plugins`), add a
`MACROS` row with swift-syntax, a module and test targets that list it, and a `Tests/CompileFailures`
fixture to a `--library --benchmarks --mutation` render, then `just test`, `just spm-test`, the
benchmarks' release build, `just mutate <Plugin>`, and `bazel test //...` in the CI image too. For a
change to how command plugins build (`PLUGINS`), add a row and a `Plugins/<name>` that writes a file
to a `--library --benchmarks --mutation` render, then `just modules`, `just spm`, `swift package
--allow-writing-to-package-directory <verb>`, `just test`, the benchmarks' release build and
`just mutate Greetings`. For a change to how modules that import Testing build (`TESTING_MODULES`,
the docs' developer search paths), add one with a public `#expect` helper, listed in
`NON_UMBRELLA_MODULES` too, and a test target using it to a `--library` render, then `just test`,
`just docs`, `just spm` and `just spm-test`. For a change to how resources build (`RESOURCES`, `tools/resources.bzl`), give `Greetings` a `Data/greetings.json` (`process`), a `PrivacyInfo.xcprivacy` and a `Fixtures/` directory (`copy`), and tests that read each through `Bundle.module` (through a `package` function of the module), in a `--library --benchmarks --mutation` render, then `just test`, `just spm-test`, `just docs`, `bazel test //Tests/GreetingsTests:GreetingsTestsBundle` (the rules_apple bundle, whose `.xctest` must hold `Contents/Resources/<Name>_Greetings.bundle`), the benchmarks' release build, `just mutate Greetings` and `bazel test //...` in the CI image; the same in an `--app` render with a resource in an iOS module and a simulator test reading both, then `just test` and `bazel build //Apps/<Name>` (the `.ipa` holds both bundles). For a change to how simulator tests build or mutate
(`SIMULATOR_TESTS`, `simulator_test`, `run_simulated`), add a module with code under
`#if canImport(UIKit)`, its test target in `SIMULATOR_TESTS` and a spec with a mutant only the
simulator catches to an `--app --mutation` render, then `just test`, `just spm-test` and
`just mutate <Module> --all`.

After a change to `template.py` (or to what `add` and `remove` merge), `python3 template_test.py`:
it commits a copy of this checkout, working tree included, in a scratch repository, then checks that
`add --wasm` and `remove --wasm` turn a stamped project into a fresh render with or without the
option plus the project's own edits, and that `remove` refuses what it should. Like `template.py`,
bootstrap leaves it out of projects.

Write each commit so it stands alone: projects receive template commits through
`just template-update`, and a commit is what they review.

## License

Apache 2.0. See [`LICENSE`](../LICENSE).
