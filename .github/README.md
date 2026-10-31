# ProjectTemplate

A starting point for Swift projects. One command creates a Swift library or a Vapor server that
already builds, tests, documents itself, releases on every push and, for servers, ships a Docker
image and optionally deploys to Fly.io. When the template improves, the projects made from it pull
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
- **Benchmarks** (optional): a separate package on
  [ordo-one/benchmark](https://github.com/ordo-one/benchmark), with wall-clock baselines and,
  with BenchmarkHarness (a separate tool, checked out alongside), simulated instruction and cache
  counts that stay steady on a busy machine.

A server adds a Vapor application, a production Docker image, a k6 load test against that image
(`just load`) and, optionally, Fly.io deployment and a SQLite database replicated with Litestream.

## Requirements

macOS with Xcode's Swift 6.3 toolchain, and from Homebrew: `bazelisk`, `just`. Benchmarks need
`jemalloc`; servers need Docker and, for the load test, `k6`; Fly.io deployment needs `flyctl`.

## Starting a project

```sh
./bootstrap.sh MyThing                                   # asks for the type and options
./bootstrap.sh MyThing ~/somewhere/MyThing               # another destination
./bootstrap.sh --library --benchmarks MyLibrary          # a library with benchmarks
./bootstrap.sh --server --fly --database MyService       # a server on Fly.io with SQLite
./bootstrap.sh --server --yes MyService                  # a server, nothing optional, no prompts
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

### Options

| Option | Adds |
|---|---|
| `--benchmarks` | `Benchmarks/`: a separate SwiftPM package, `BASELINE` entries, `just bench`, `bench-baseline`, `bench-compare`, and `bench-simulated` / `bench-simulated-compare` (Callgrind in a Linux VM through BenchmarkHarness, a separate tool expected at `~/workspace/BenchmarkHarness` or `$BENCHMARK_HARNESS`). The `main` and `simulated` baselines are committed. |
| `--mutation` | `scripts/mutate.py` and `just mutate <Module>`: the planted bugs in `scripts/mutants/<Module>.py` (a `Greetings` example), compiled into one build of a scratch copy behind runtime switches; each must make a test fail. Results are stored by a hash of everything a mutant depends on, so a rerun tests only what changed; `--select` runs coverage-selected tests first. |
| `--fly` (server) | `fly.toml` (suspend when idle, `/health` checks), a `deploy` job in `Release.yml` after CI (`FLY_API_TOKEN` secret), `just deploy`. Without it nothing deploys. |
| `--database` (server) | Fluent with SQLite in WAL mode: the file at `DATABASE_PATH`, memory when unset (production refuses to start without it); an example model and migration; a volume mount in `fly.toml`. |
| `--fly --database` | Litestream: `litestream.yml` replicates to Backblaze B2 (the `B2_*` Fly secrets), and `scripts/docker-entrypoint.sh` restores the database onto an empty volume, then runs the server under `litestream replicate`. Without the secrets it serves unreplicated. With one machine and one volume, Litestream runs directly, without LiteFS. |

## Keeping projects current

The template is versioned by its git commits (each push to `main` is also tagged). Every project
`bootstrap.sh` makes carries `.template.json`: the commit it came from, its name and its options.
`template.py` uses it to carry later template changes into the project.

```sh
just template-update                           # inside a project
./template.py update ~/workspace/MyProject     # the same, from the template
./template.py status                           # every project in ~/workspace and how far behind it is
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

Every optional piece (`benchmarks`, `mutation`, `library`, `server`, `fly`, `database`, `litestream`) keeps
or drops the sections marked for it, in any text file:

- `# feature:begin` / `# feature:end` blocks (`//` in Swift and JavaScript, `<!-- -->` in
  Markdown); blocks nest, and `!feature:begin` / `!feature:end` marks a block kept when the
  feature is off;
- single lines ending in `# feature:line` or holding `<!-- feature:line -->` (table rows carry it
  inside their last cell, so the table still renders);
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
| Remote cache hook | `user.bazelrc.example`, CI | BuildBuddy, optional |
| Xcode project from the graph | `just generate` | rules_xcodeproj; schemes derived from `Tests/*` |
| DocC site | `tools/docc.bzl`, `just docs`, `docc.yml` | One archive per module, merged; published to gh-pages |
| Benchmarks (opt-in) | `Benchmarks/` | Separate package, ordo-one/benchmark, `BASELINE` entries, committed `main` and `simulated` baselines |
| Mutation testing (opt-in) | `scripts/mutate.py`, `scripts/mutants/` | Mutant schemata over a scratch SwiftPM copy outside the repository (`~/Library/Caches/<project>-mutation`); `<PROJECT>_MUTANT` picks the live mutant |
| Mocks (off until needed) | `scripts/modules.py` (`MOCKING`), `tools/BUILD.bazel` | Mockable row commented out in `PACKAGES`; a module depending on it gets `MOCKING` in debug only, in both build systems |
| CI | `.github/workflows` | Linux arm64 Bazel tests on branches and PRs; tag-and-release on main |
| Test support | `Tests/ProjectNameTestSupport` | Seeded RNG, tags; data only |
| Executables | `EXECUTABLES` in `scripts/modules.py` | `.executableTarget` in SwiftPM, `swift_binary` in Bazel, a run scheme in Xcode; left out of the umbrella and the docs |
| Server type | `templates/server/` | Vapor, Docker, a k6 load test, optionally Fly.io, SQLite and Litestream |
| Example module | `Sources/Greetings`, `Tests/GreetingsTests` | The house style: composable value type, plain/checked spellings, hand-worked, edge, exit and property tests |
| Agent instructions | `AGENTS.md` (`CLAUDE.md` includes it) | Layout, commands, building blocks, feature checklist, house rules, API conventions |
| Claude permissions | `.claude/settings.json` | `just`, `bazel build/test/query`, read-only git |

Not included, available in [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) to
copy: libFuzzer targets (`Fuzz/`), differential testing against Python libraries
(`Differential/`), WebAssembly test runs, the browser explorer.

### Checking a change

Validate the template in place after editing: `just modules && just test && just spm-test &&
just docs`. After touching a marked section, bootstrap each variant it affects into a scratch
directory with `--yes` and check them: `--library` with and without `--benchmarks`; `--server`
alone, with `--database`, and with `--fly --database`. For a server change, also run `just spm`
and `just load` in the bootstrapped project.

Write each commit so it stands alone: projects receive template commits through
`just template-update`, and a commit is what they review.

## License

Apache 2.0. See [`LICENSE`](../LICENSE).
