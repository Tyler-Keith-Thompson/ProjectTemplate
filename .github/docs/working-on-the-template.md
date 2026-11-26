# Working on the template


The template is itself a working library project under the placeholder name `ProjectName`: the
root `README.md`, `AGENTS.md` and the rest are what every new project starts with. The template's
own README (`.github/README.md`, which GitHub shows in place of the root one), these pages
(`.github/docs/`), `bootstrap.sh`, `template.py`
and `templates/` stay behind.

## Optional pieces

Every optional piece (`benchmarks`, `mutation`, `fuzz`, `differential`, `wasm`, `explore`, `views`, `examples`, `ios`, `performance`, `library`, `server`, `embedded`, `mcp`, `app`, `fly`, `database`, `litestream`, `swiftui`, `simulator`, `wasi`, `ci`, `trunk`) keeps
or drops the sections marked for it, in any text file. `litestream` is on with `fly` and `database`
together, `swiftui` with `app` or `views` (the lint stack and view-test packages they share), `simulator`
with `app`, `ios` or the `--simulator` option (the test host, `.bazelrc`'s simulator settings and `tools/ios.bzl`), and
`wasi` with `wasm` or `explore`: what any build for wasm32-wasi needs, `NON_WASI_PACKAGES` and its
manifest condition, so a render without either names neither WASI nor wasm. `template` is never on
in a render: it marks what only the template's checkout needs, such as `.bazelignore`'s `templates`.

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

## Where things are

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
| Simulator tests beside the Mac's | `SIMULATOR_TESTS` in `scripts/modules.py` | Empty until a project adds one. A listed test target keeps its Package.swift target, swift_test and Xcode bundle, and gains `<Target>Simulator`, an `ios_unit_test` hosted by `tools/test_host` (tagged `manual`, so Linux never builds it), incompatible off macOS, of `<Target>SimulatorLibrary`: the same sources built for iOS alone, with Apple-only products listed plainly and without the Mac library's `data`, which rules_apple would flatten into the bundle as resources. `check()` refuses an unknown target, one that runs in the simulator alone already (an iOS module or a `//` label among its dependencies), and any simulator test (listed, or of an iOS module) without `tools/test_host` and `.bazelrc`'s `--local_resources=simulator`, which only the app type and `--ios` ship; without them it refuses `IOS_MODULES` too, as the root BUILD then has no `tools/ios.bzl`. The Mac half must run at least one test (rules_swift's runner fails a run of none). Checked on scratch app and `--views` renders with a sample row, since the template ships none |
| Macros | `MACROS` in `scripts/modules.py`, `tools/swift_rules.bzl`, `tools/compile_failure_test.bzl` | Empty until a project adds one. A row is a compiler plugin: a `.macro` target in Package.swift and a `swift_compiler_plugin` in Bazel, in the `plugins` of each module that lists it; a test target that lists it links `<Plugin>Library`, its sources compiled as a library in the test's package with the entry point renamed. No product, docs or umbrella import (`tools/macros.bzl`, generated, tells the root BUILD). `//:package_swift_test`, the benchmarks' source aspect and `scripts/mutate.py` follow plugins as dependencies. `swift_compile_failure_test` type-checks a fixture in `Tests/CompileFailures` (left out of the test bundles by name) with the plugin loaded and passes when the expected errors appear. Checked on a scratch render with a sample row, since the template ships none |
| Command plugins | `PLUGINS` in `scripts/modules.py`, `Plugins/<name>/` | Empty until a project adds one. A row (name, verb, description, reason) is a `.plugin` target and product in Package.swift, run with `swift package <verb>`; a reason asks for `.writeToPackageDirectory`, `None` for no permissions. Bazel builds none of it: no BUILD.bazel in `Plugins/`, and `//:package_swift_test` and `//:docs` read only `Sources/` and `Tests/`. `check()` refuses a duplicate name or verb, a name taken by a module, macro, executable or test target, and a plugin with no Swift sources. `scripts/mutate.py` leaves plugins out of its pruned manifest, the benchmarks stage a placeholder source for each, and the server image's context lets `Plugins/` in. Checked on a scratch render with a sample row, since the template ships none |
| Server type | `templates/server/` | Vapor, Docker, a k6 load test, optionally Fly.io, SQLite and Litestream |
| MCP type | `templates/mcp/` | `Tools` (`ToolServer`, `ToolHandler`), the stdio executable, `just install` |
| App type | `templates/app/`, `IOS_MODULES` in `scripts/modules.py` | iOS modules get `target_compatible_with` iOS and no docs; Package.swift declares only the packages its own targets use; a test target depending on one becomes an `ios_unit_test` hosted by `tools/test_host` (a logic test can't give a window a scene) on rules_apple's default runner, which drives `xcodebuild`, with a `Snapshots` resource bundle; `tools/ios.bzl` (generated) tells the root BUILD which packages to leave out of the docs and `//:package_swift_test`. Lint is an aspect (`tools/lint.bzl`) over `swift_library` targets with no external workspace |
| Views option | `templates/views/`, `APPLE_ONLY_PACKAGES` and `APPLE_ONLY_TESTS` in `scripts/modules.py` | A library's SwiftUI modules: `#if canImport(SwiftUI)` sources, tests on the Mac under `#if os(macOS)`; a test target on SnapshotTesting gets `__Snapshots__` as `data` (Bazel) and excluded (SwiftPM). Lint (`tools/lint.bzl`, `third_party/`, `.swiftlint*.yml`) is shared with the app type, marked `swiftui` |
| Embedded type | `templates/embedded/`, `FIRMWARE_MODULES` in `scripts/modules.py` | `embedded_swift_module` per firmware module and `embedded_swift_firmware` (`tools/embedded.bzl`); the ESP-IDF build runs Bazel before compiling the app, checks the modules' architecture against the chip's, and keeps the GOT that Swift's position-independent code needs (`Firmware/main/swift.lf`) |
| Example module | `Sources/Greetings`, `Tests/GreetingsTests` | The house style: composable value type, a plain spelling that throws (trap and `checked:` spellings with exit tests under `performance`, dormant `//|` lines here, so the template's own build tests the throwing one), hand-worked, edge and property tests |
| Agent instructions | `AGENTS.md` (`CLAUDE.md` includes it) | Layout, commands, building blocks, feature checklist, house rules, API conventions |
| Claude permissions | `.claude/settings.json` | `just`, `bazel build/test/query`, read-only git |


## Checking a change

The template repository runs no CI, so these local checks are all that stands behind a push.

1. Validate the template in place: `just modules && just test && just spm-test && just docs`.
2. After touching a marked section, bootstrap each variant it affects into a scratch directory
   with `--yes` and test it:
   - `--library`, alone and with each of `--benchmarks`, `--mutation`, `--fuzz`, `--differential`,
     `--wasm` and `--explore`;
   - `--server` alone, with `--database`, and with `--fly --database`;
   - `--embedded` alone and with `--wasm`;
   - `--mcp`;
   - `--app` alone and with `--benchmarks --mutation`;
   - `--library --views`, `--library --ios`, `--server --ios` and `--library --simulator`;
   - after touching anything marked `performance` (the Greetings example and every sample that
     calls it), `--library --performance` and `--server --performance`, with
     `--benchmarks --mutation --fuzz --differential --explore` on the library.
3. Run what the change touches in the bootstrapped project:

| Change | Also run |
|---|---|
| Server | `just spm`, `just load` |
| Fuzzing | `just fuzz -t 30`, `just fuzz-regress` |
| Differential | `just diff` |
| WebAssembly | `just wasi-test` |
| Explorer | `just explore` |
| Embedded | `just firmware` |
| MCP | `INSTALL_DIR=<scratch> just install`, then pipe an `initialize`, `tools/list` and `tools/call` into the installed binary |
| App | `just lint`, `just smoke`, and after a change to how a screen looks, `just record-snapshots` with the images reviewed |
| Views | `just spm-test`, and after a change to how a view looks, `just record-snapshots` with the images reviewed, then the references copied back into `templates/views` |
| How macros build (`MACROS`, `tools/compile_failure_test.bzl`, what follows `plugins`) | In a `--library --benchmarks --mutation` render, add a `MACROS` row with swift-syntax, a module and test targets that list it, and a `Tests/CompileFailures` fixture; then `just test`, `just spm-test`, the benchmarks' release build, `just mutate <Plugin>`, and `bazel test //...` in the CI image |
| How command plugins build (`PLUGINS`) | In a `--library --benchmarks --mutation` render, add a row and a `Plugins/<name>` that writes a file; then `just modules`, `just spm`, `swift package --allow-writing-to-package-directory <verb>`, `just test`, the benchmarks' release build and `just mutate Greetings` |
| How modules that import Testing build (`TESTING_MODULES`, the docs' developer search paths) | In a `--library` render, add one with a public `#expect` helper, listed in `NON_UMBRELLA_MODULES` too, and a test target using it; then `just test`, `just docs`, `just spm` and `just spm-test` |
| How resources build (`RESOURCES`, `tools/resources.bzl`) | In a `--library --benchmarks --mutation` render, give `Greetings` a `Data/greetings.json` (`process`), a `PrivacyInfo.xcprivacy` and a `Fixtures/` directory (`copy`), and tests that read each through `Bundle.module` (through a `package` function of the module); then `just test`, `just spm-test`, `just docs`, `bazel test //Tests/GreetingsTests:GreetingsTestsBundle` (its `.xctest` must hold `Contents/Resources/<Name>_Greetings.bundle`), the benchmarks' release build, `just mutate Greetings` and `bazel test //...` in the CI image. Then the same in an `--app` render with a resource in an iOS module and a simulator test reading both: `just test`, and `bazel build //Apps/<Name>` (the `.ipa` holds both bundles) |
| How simulator tests build or mutate (`SIMULATOR_TESTS`, `simulator_test`, `run_simulated`) | In an `--app --mutation` render, add a module with code under `#if canImport(UIKit)`, its test target in `SIMULATOR_TESTS`, and a spec with a mutant only the simulator catches; then `just test`, `just spm-test` and `just mutate <Module> --all` |

After a change to `template.py` (or to what `add` and `remove` merge), run
`python3 template_test.py`. It commits a copy of this checkout, working tree included, to a scratch
repository, then checks that `add` and `remove` turn a stamped project into a fresh render with or
without an option plus the project's own edits, that they refuse what they should, and that a render
leaves out what git ignores. Like `template.py`,
bootstrap leaves it out of projects.

Write each commit so it stands alone: projects receive template commits through
`just template-update`, and a commit is what they review.
