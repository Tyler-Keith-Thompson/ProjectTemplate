# Project template

A Swift package the way the owner likes it: Bazel for development, SwiftPM for publishing, both
generated from one module table, a justfile over the top, Swift Testing, DocC, benchmarks and
agent instructions. Lifted from [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent)
and [Laminar](../Laminar).

## Start a project

```sh
./bootstrap.sh MyThing                                   # asks for the type and options
./bootstrap.sh MyThing ~/somewhere/MyThing               # another destination
./bootstrap.sh --library --benchmarks MyLibrary          # a library with benchmarks
./bootstrap.sh --server --fly --database MyService       # a server on Fly.io with SQLite
./bootstrap.sh --server --yes MyService                  # a server, nothing optional, no prompts
```

The destination defaults to `~/workspace/<Name>`. Run from a terminal, the script asks for the
type and every option not given as a flag; otherwise (or with `--yes`) those default to off. It
copies the template, renames `ProjectName`/`projectname` to the new name, stamps it with
`.template.json`, runs `just modules`, `git init`, `just resolve` and `just test`, then prints what
to fill in.

### Types

| Type | What it adds |
|---|---|
| `library` (default) | Nothing: the template as it stands. A Swift package published through SwiftPM, with README examples as tests (`Tests/ProjectNameTests`). |
| `server` | `templates/server/` on top: a Vapor `App` module (`configure(_:)`, routes), a `ProjectNameServer` executable, `AppTests` (VaporTesting), a Dockerfile building with SwiftPM pinned by `swift/Package.resolved`, `just run`, `just docker`, and a k6 load test (`LoadTests/load.js`, `just load`) against a fresh production image. Platforms narrow to macOS; the README's installation section and README tests are dropped. |

Server options, each off unless asked for:

| Option | Adds |
|---|---|
| `--fly` | `fly.toml` (suspend when idle, `/health` checks), a `deploy` job in `Release.yml` after CI (`FLY_API_TOKEN` secret), `just deploy`. Without it nothing deploys. |
| `--database` | Fluent with SQLite in WAL mode: the file at `DATABASE_PATH`, memory when unset (production refuses to start without it); an example model and migration; a volume mount in `fly.toml`. |
| `--fly --database` | Litestream: `litestream.yml` replicates to Backblaze B2 (the `B2_*` Fly secrets), and `scripts/docker-entrypoint.sh` restores the database onto an empty volume, then runs the server under `litestream replicate`. Without the secrets it serves unreplicated. |

The deployment follows MUDGame's (`~/workspace/MUDGame`), less LiteFS: with one machine and a
volume, LiteFS added a FUSE mount and nothing else, so Litestream runs directly.

### Optional pieces

Every optional piece (`benchmarks`, `library`, `server`, `fly`, `database`, `litestream`) keeps
or drops the sections marked for it, in any text file:

- `# feature:begin` / `# feature:end` blocks (`//` in Swift, `<!-- -->` in Markdown); blocks
  nest, and `!feature:begin` / `!feature:end` marks a block kept when the feature is off;
- single lines ending in `# feature:line` or holding `<!-- feature:line -->` (table rows carry it
  inside their last cell, so the table still renders);
- dormant lines, `#| code` or `//| code`, inside a block or on a marked line: comments in the
  template, uncommented when kept. They are how `scripts/modules.py` and `MODULE.bazel` carry the
  server's rows without the template building them in place.

The markers are removed either way. Whole files that belong to one piece are listed in
`bootstrap.sh` (`remove_unless`). When adding anything optional to the template, mark it the same
way. Keep a numbered-list item that gets marked last in its list, so removing it leaves the
numbering intact.

## What is in it

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
| Benchmarks (opt-in) | `Benchmarks/` | Separate package, ordo-one/benchmark, `BASELINE` entries, committed `main` and `simulated` (Callgrind, via `~/workspace/BenchmarkHarness`) baselines; `--benchmarks` |
| Mocks (off until needed) | `scripts/modules.py` (`MOCKING`), `tools/BUILD.bazel` | Mockable row commented out in `PACKAGES`; a module depending on it gets `MOCKING` in debug only, in both build systems |
| CI | `.github/workflows` | Linux arm64 Bazel tests on branches and PRs; tag-and-release on main |
| Test support | `Tests/ProjectNameTestSupport` | Seeded RNG, tags; data only |
| Executables | `EXECUTABLES` in `scripts/modules.py` | `.executableTarget` in SwiftPM, `swift_binary` in Bazel, a run scheme in Xcode; left out of the umbrella and the docs |
| Server type | `templates/server/` | Vapor, Docker, a k6 load test (`just load`), optionally Fly.io, SQLite and Litestream (see Types) |
| Example module | `Sources/Greetings`, `Tests/GreetingsTests` | The house style: composable value type, plain/checked spellings, hand-worked, edge, exit and property tests |
| Agent instructions | `AGENTS.md` (`CLAUDE.md` includes it) | Layout, commands, building blocks, feature checklist, house rules, API conventions |
| Claude permissions | `.claude/settings.json` | `just`, `bazel build/test/query`, read-only git |

Not included, available in Grafluent to copy: mutation testing (`scripts/mutate.py`), libFuzzer
targets (`Fuzz/`), differential testing against Python libraries (`Differential/`), WebAssembly
test runs, the browser explorer.

## Keeping the template current

Validate it in place after editing: `just modules && just test && just spm-test && just docs`.
The template itself builds under the placeholder name.
After touching a marked section, bootstrap each variant it affects into a scratch directory with
`--yes` and check them: `--library` with and without `--benchmarks`; `--server` alone, with
`--database`, and with `--fly --database`. For a server change, also run `just spm` and
`just docker` in the bootstrapped project.

## Updating projects

The template is versioned by its git commits. Every project `bootstrap.sh` makes carries
`.template.json`: the commit it came from, its name and its options. `template.py` uses the stamp to
carry later template changes into the project.

```sh
./template.py status                       # every project in ~/workspace and how far behind it is
./template.py update ~/workspace/MyProject # or `just template-update` inside the project
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
Write template commits so they stand alone: each is what a project receives.

A project made before stamps existed is adopted with `./template.py stamp <project> --type …
[--benchmarks] [--fly] [--database]`, which records that it matches the template's `HEAD`. Later
updates merge only what changes after that. To see how far it had drifted first, render the
template with its options (`./bootstrap.sh --render-only --type … <Name> <scratch directory>`) and
compare with `git diff --no-index`.
