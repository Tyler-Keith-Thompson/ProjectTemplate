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

## Requirements

macOS with Xcode's Swift 6.3 toolchain, and from Homebrew: `bazelisk`, `just`. Benchmarks need
`jemalloc`; servers need Docker and, for the load test, `k6`; Fly.io deployment needs `flyctl`;
`just ci-secrets` needs `gh`, signed in. Fuzzing needs `swiftly` with a swift.org toolchain
(`swiftly install 6.3.3`), since Xcode's has no libFuzzer runtime. Differential testing needs
`uv`. WebAssembly tests need swiftly's toolchain, its Swift SDK for WebAssembly and `wasmtime`; the
explorer needs the same toolchain and SDK, and `binaryen` for `wasm-opt`. Firmware needs swiftly's
Swift 6.3.3 (`swiftly install 6.3.3`), since Xcode's toolchain has no Embedded Swift for RISC-V, and
[ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/get-started/) 5.5 in
`~/esp/esp-idf` or `IDF_PATH`, for building the image.

## Starting a project

```sh
./bootstrap.sh MyThing                                   # asks for the type and options
./bootstrap.sh MyThing ~/somewhere/MyThing               # another destination
./bootstrap.sh --library --benchmarks MyLibrary          # a library with benchmarks
./bootstrap.sh --server --fly --database MyService       # a server on Fly.io with SQLite
./bootstrap.sh --server --yes MyService                  # a server, nothing optional, no prompts
./bootstrap.sh --embedded --wasm MyGadget                # ESP32 firmware, its tests also on a 32-bit Int
./bootstrap.sh --mcp MyTools                             # an MCP server for Claude Code
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
| `--fly` (server) | `fly.toml` (suspend when idle, `/health` checks), a `deploy` job in `Release.yml` after CI (`FLY_API_TOKEN` secret), `just deploy`. Without it nothing deploys. |
| `--database` (server) | Fluent with SQLite in WAL mode: the file at `DATABASE_PATH`, memory when unset (production refuses to start without it); an example model and migration; a volume mount in `fly.toml`. |
| `--fly --database` | Litestream: `litestream.yml` replicates to Backblaze B2 (the `B2_*` Fly secrets), and `scripts/docker-entrypoint.sh` restores the database onto an empty volume, then runs the server under `litestream replicate`. Without the secrets it serves unreplicated. With one machine and one volume, Litestream runs directly, without LiteFS. |
| `--no-ci` | Removes `.github/workflows/` (CI, PR CI, Release, DocC) and everything that leans on it: `just ci-secrets`, the documentation link, the release and push rules in AGENTS.md. With `--fly`, `just deploy` is the only deploy; with `--explore`, `just explore` builds the site locally and nothing publishes it. CI is the one option on by default, and the only question asked as [Y/n]. |

## Keeping projects current

The template is versioned by its git commits (each push to `main` is also tagged). Every project
`bootstrap.sh` makes carries `.template.json`: the commit it came from, its name and its options.
`template.py` uses it to carry later template changes into the project.

```sh
just template-update                           # inside a project
./template.py update ~/workspace/MyProject     # the same, from the template
./template.py status                           # every project in ~/workspace and how far behind it is
./template.py add ~/workspace/MyProject --wasm # turn an option on in a project made without it
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
Projects find the template at `~/workspace/ProjectTemplate`, or `$PROJECT_TEMPLATE`.

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

Every optional piece (`benchmarks`, `mutation`, `fuzz`, `differential`, `wasm`, `explore`, `library`, `server`, `embedded`, `mcp`, `fly`, `database`, `litestream`, `ci`) keeps
or drops the sections marked for it, in any text file:

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
| One module table | `scripts/modules.py` | Writes `Package.swift`, every `BUILD.bazel`, the umbrella, `swift/Package.swift`; `//:package_swift_test` keeps them honest |
| Warnings as errors | `tools/swift_rules.bzl` | First-party only; dependencies build quietly (`.bazelrc`) |
| Swift 6 mode, one package name | `tools/swift_rules.bzl` | So `package` access and retroactive conformances agree with SwiftPM |
| Debug default, release config | `.bazelrc`, `justfile` | Release uses its own output base; `debug-only` tags keep ordinary tests out of release |
| Analysis-cache guardrail | `.bazelrc` | `--noallow_analysis_cache_discard` |
| Remote cache | `tools/bazel`, `tools/buildbuddy.bazelrc`, `tools/buildbuddy-credentials`, CI | BuildBuddy, on when the login Keychain holds the key: Bazelisk runs `tools/bazel`, which adds the BuildBuddy rc file, and a credential helper hands Bazel the key per request. CI writes the same flags from the `BUILDBUDDY_API_KEY` secret (`just ci-secrets`). `user.bazelrc.example` is the manual setup for a machine without a Keychain. |
| Xcode project from the graph | `just generate` | rules_xcodeproj; schemes derived from `Tests/*` |
| DocC site | `tools/docc.bzl`, `just docs`, `docc.yml` | One archive per module, merged; published to gh-pages |
| Benchmarks (opt-in) | `Benchmarks/` | Separate package, ordo-one/benchmark, `BASELINE` entries, committed `main` and `simulated` baselines |
| Mutation testing (opt-in) | `scripts/mutate.py`, `scripts/mutants/` | Mutant schemata over a scratch SwiftPM copy outside the repository (`~/Library/Caches/<project>-mutation`); `<PROJECT>_MUTANT` picks the live mutant |
| Fuzzing (opt-in) | `Fuzz/`, `scripts/fuzz.py` | libFuzzer through `LLVMFuzzerRunDriver` (each target's `@main` calls `runFuzzer`); swiftly's toolchain, `<PROJECT>_FUZZ_SWIFT` picks its version; corpus in `Fuzz/Corpus/`, crashes in `Fuzz/Crashes/` |
| Differential testing (opt-in) | `Differential/`, `scripts/differential*.py` | `DIFFERENTIAL_DEPENDENCIES` in `scripts/modules.py` writes the package's BUILD.bazel and Package.swift; areas are discovered by file name |
| WebAssembly tests (opt-in) | `scripts/wasi_test.py`, `scripts/modules.py` | The generated `Package.swift` reads `<PROJECT>_WASI_TESTS` (marked `wasm` in the generator); builds in `.build/wasm` |
| Browser explorer (opt-in) | `Explore/`, `docc.yml` | ElementaryUI and JavaScriptKit (PackageToJS); the workflow job is dormant (`#|`) in the template, so only `--explore` projects run it |
| Mocks (off until needed) | `scripts/modules.py` (`MOCKING`), `tools/BUILD.bazel` | Mockable row commented out in `PACKAGES`; a module depending on it gets `MOCKING` in debug only, in both build systems |
| CI | `.github/workflows` | Linux arm64 Bazel tests on branches and PRs; tag-and-release on main |
| Test support | `Tests/ProjectNameTestSupport` | Seeded RNG, tags; data only |
| Executables | `EXECUTABLES` in `scripts/modules.py` | `.executableTarget` in SwiftPM, `swift_binary` in Bazel, a run scheme in Xcode; left out of the umbrella and the docs |
| Server type | `templates/server/` | Vapor, Docker, a k6 load test, optionally Fly.io, SQLite and Litestream |
| MCP type | `templates/mcp/` | `Tools` (`ToolServer`, `ToolHandler`), the stdio executable, `just install` |
| Embedded type | `templates/embedded/`, `FIRMWARE_MODULES` in `scripts/modules.py` | `embedded_swift_module` per firmware module and `embedded_swift_firmware` (`tools/embedded.bzl`); the ESP-IDF build runs Bazel before compiling the app, checks the modules' architecture against the chip's, and keeps the GOT that Swift's position-independent code needs (`Firmware/main/swift.lf`) |
| Example module | `Sources/Greetings`, `Tests/GreetingsTests` | The house style: composable value type, plain/checked spellings, hand-worked, edge, exit and property tests |
| Agent instructions | `AGENTS.md` (`CLAUDE.md` includes it) | Layout, commands, building blocks, feature checklist, house rules, API conventions |
| Claude permissions | `.claude/settings.json` | `just`, `bazel build/test/query`, read-only git |


### Checking a change

Validate the template in place after editing: `just modules && just test && just spm-test &&
just docs`. After touching a marked section, bootstrap each variant it affects into a scratch
directory with `--yes` and check them: `--library` with and without `--benchmarks`, `--mutation`, `--fuzz`, `--differential`, `--wasm` and `--explore`; `--server`
alone, with `--database`, and with `--fly --database`; `--embedded` alone and with `--wasm`; `--mcp`. For a server change, also run `just spm`
and `just load` in the bootstrapped project; for a fuzz change, `just fuzz -t 30` and
`just fuzz-regress`; for a differential change, `just diff`; for a WebAssembly change, `just wasi-test`; for an explorer change, `just explore`; for an
embedded change, `just firmware` in the bootstrapped project; for an MCP change, `INSTALL_DIR=<scratch> just install`
and an `initialize`, `tools/list` and `tools/call` piped into the installed binary.

Write each commit so it stands alone: projects receive template commits through
`just template-update`, and a commit is what they review.

## License

Apache 2.0. See [`LICENSE`](../LICENSE).
