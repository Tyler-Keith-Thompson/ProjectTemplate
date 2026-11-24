# ProjectTemplate

One command makes a new Swift project that already builds, tests and documents itself. When the
template changes, projects made from it pull the change in with `just template-update`.

```sh
git clone https://github.com/Tyler-Keith-Thompson/ProjectTemplate ~/workspace/ProjectTemplate
~/workspace/ProjectTemplate/bootstrap.sh MyThing
```

The script asks for the type and options, writes `~/workspace/MyThing`, resolves its dependencies
and runs its tests. Nothing in the project depends on the template after that.

You need macOS with Xcode's Swift 6.3 toolchain, and `bazelisk` and `just` from Homebrew. Some
options need more; [What a new project has](docs/projects.md#requirements) lists them.

## Types

| Type | What you get |
|---|---|
| `library` (default) | A Swift package published through SwiftPM |
| `server` | A Vapor server with a Docker image and a k6 load test |
| `mcp` | An MCP server for Claude Code |
| `app` | An iOS app in SwiftUI |
| `embedded` | ESP32 firmware in Embedded Swift |

Every type gets Bazel for development and SwiftPM for publishing, both written from one module
table, plus a justfile, Swift Testing, DocC and an `AGENTS.md` for coding agents. Every type but
`app` also gets GitHub Actions CI, which releases a patch version on each push to `main`; an iOS
app's tests need a Mac, and the workflows run on Linux.

## Options

| Option | Adds |
|---|---|
| `--benchmarks` | Benchmarks, with instruction counts that hold steady on a busy machine |
| `--mutation` | Mutation testing: planted bugs the tests must catch |
| `--fuzz` | libFuzzer targets checked against a model |
| `--differential` | Seeded cases compared against reference implementations |
| `--wasm` | The test suites run as WebAssembly, where `Int` is 32 bits (library, embedded) |
| `--explore` | Browser pages that run the library as WebAssembly (library) |
| `--views` | A SwiftUI view module with view and snapshot tests (library) |
| `--examples` | Example apps in a package of their own (library) |
| `--ios` | An iOS app beside a library or server |
| `--fly`, `--database` | Fly.io deployment; a SQLite database, replicated with Litestream when both are on (server) |
| `--no-ci` | No GitHub Actions |
| `--trunk` | Pull requests merge through Trunk's merge queue (with CI) |

```sh
./bootstrap.sh --library --benchmarks MyLibrary
./bootstrap.sh --server --fly --database MyService
./bootstrap.sh --app MyApp
```

## Keeping projects current

```sh
just template-update                                    # inside a project
./template.py status                                    # every project and how far behind it is
./template.py add ~/workspace/MyProject --wasm          # turn an option on later
./template.py remove ~/workspace/MyProject --wasm       # or off
./template.py retype ~/workspace/MyProject --type mcp   # change the type
```

Each command merges the template's changes into the project three ways and never commits, so
`git diff` shows what it did.

## More

- [What a new project has](docs/projects.md): each type and option in full, and what each needs
  installed
- [Keeping projects current](docs/updating.md): how `update`, `add`, `remove`, `retype` and `stamp`
  merge, and what to do with conflicts and duplicates
- [Working on the template](docs/working-on-the-template.md): feature markers, where each piece
  lives, and what to check before pushing

## License

Apache 2.0. See [`LICENSE`](../LICENSE).
