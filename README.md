# ProjectName

<One paragraph: what the package is and what it is for.>

[Documentation](https://tyler-keith-thompson.github.io/ProjectName/documentation/) <!-- ci:line -->
<!-- library:begin -->

## Installation

ProjectName requires Swift 6.3 and supports macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2
or later.

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/ProjectName", from: "0.0.1"),
],
```

Then add a product to your target, either the umbrella or individual modules:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "ProjectName", package: "ProjectName"),
    // or, for example:
    // .product(name: "Greetings", package: "ProjectName"),
]),
```

## Usage

Every example here is a test in `Tests/ProjectNameTests`, so it cannot drift from the code.

```swift
import ProjectName

let greeting = Greeting(name: "Ada").formal().punctuated(with: "!")
print(greeting.text)  // Good day, Ada!
```
<!-- library:end -->
<!-- server:begin -->

## Running

ProjectName is a [Vapor](https://vapor.codes) server and requires Swift 6.3 on macOS 15 or Linux.

```sh
just run                          # http://localhost:8080
curl localhost:8080/hello/Ada     # Good day, Ada!
<!-- database:begin -->
curl localhost:8080/hello/Ada/count
<!-- database:end -->
just docker                       # the production image, on the same port
```

<!-- database:begin -->
The database is SQLite: the file named by `DATABASE_PATH`, or memory when that is unset (production
refuses to start without it). `just run` keeps it in `.build/projectname.sqlite`.

<!-- database:end -->
<!-- fly:begin -->
## Deployment

Every push to `main` that passes CI deploys to [Fly.io](https://fly.io) (`fly.toml`, the `deploy` <!-- ci:line -->
job in `.github/workflows/Release.yml`); `just deploy` deploys a local checkout. One-time setup: <!-- ci:line -->
`just deploy` deploys this checkout to [Fly.io](https://fly.io) (`fly.toml`). One-time setup: <!-- !ci:line -->

```sh
fly launch --no-deploy --copy-config --name projectname
<!-- database:begin -->
fly volumes create data --size 1 --region den
<!-- database:end -->
fly tokens create deploy          # into the FLY_API_TOKEN secret on GitHub <!-- ci:line -->
```

<!-- litestream:begin -->
[Litestream](https://litestream.io) replicates the database to Backblaze B2 and restores it when
a machine starts on an empty volume (`litestream.yml`, `scripts/docker-entrypoint.sh`). Until its
secrets are set, the server runs without replication:

```sh
fly secrets set B2_KEY_ID=… B2_APPLICATION_KEY=… B2_BUCKET_NAME=… \
    B2_ENDPOINT=https://s3.<region>.backblazeb2.com
```

<!-- litestream:end -->
<!-- fly:end -->
<!-- server:end -->

## Modules

| Module | Holds |
|---|---|
| `Greetings` | `Greeting`: a greeting composed from a name and modifiers |
| `App` | The HTTP application: `configure(_:)` and its routes <!-- server:line --> |
| `ProjectNameServer` | The executable: `ProjectNameServer serve` <!-- server:line --> |

## Development

Bazel is the development build; SwiftPM is the published package. Both are generated from
`scripts/modules.py`.

| Command | Does |
|---|---|
| `just test` | Build and run every test |
| `just verify` | The tests under Bazel and under SwiftPM |
| `just modules` | Regenerate `Package.swift` and every `BUILD.bazel` |
| `just docs` | The DocC site into `.build/docs` |
| `just bench` | The benchmarks (`Benchmarks/README.md`) <!-- benchmarks:line --> |
| `just run` | The server on port 8080 <!-- server:line --> |
| `just docker` | The production image, built and run <!-- server:line --> |
| `just load` | A k6 load test against the production image (`brew install k6`) <!-- server:line --> |
| `just deploy` | This checkout, to Fly.io <!-- fly:line --> |
| `just generate` | An Xcode project from the Bazel graph |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

Apache 2.0. See `LICENSE`.
