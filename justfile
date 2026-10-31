PROJECT_ROOT := justfile_directory()
BAZEL := "bazel"

# Optimized builds use a separate output base: switching --compilation_mode changes the
# configuration, and sharing a base with debug builds would discard the analysis cache on every
# switch (which .bazelrc refuses).
BAZEL_RELEASE := "bazel --output_base=" + home_directory() + "/Library/Caches/bazel-projectname-release"

# SwiftPM runs through Xcode's default toolchain. A development snapshot selected through
# TOOLCHAINS (or first on PATH via swiftly) can fail to read the SDK's Testing module.
SWIFT := "env -u TOOLCHAINS xcrun --toolchain default swift"

[doc('Build everything (default)')]
all: build

[doc('Build every target')]
build:
    {{BAZEL}} build //...

[doc('Run every test')]
test:
    {{BAZEL}} test //...

[doc('Run one test target, e.g. just test-one //Tests/GreetingsTests')]
test-one target:
    {{BAZEL}} test {{target}}

[doc('Run tests matching a filter, e.g. just filter Greeting')]
filter pattern:
    {{BAZEL}} test //... --test_filter={{pattern}}

[doc('Run the speed-reliant tests (the PerformanceTests targets) optimized (-O); the rest run in debug only')]
test-release:
    {{BAZEL_RELEASE}} test --config=release //...

[doc('Re-resolve SwiftPM dependencies for Bazel after editing PACKAGES in scripts/modules.py')]
resolve:
    cd {{PROJECT_ROOT}}/swift && {{SWIFT}} package resolve

[doc('Build via SwiftPM too, to verify the published package')]
spm:
    {{SWIFT}} build

[doc('Run the tests via SwiftPM')]
spm-test *args="":
    {{SWIFT}} test {{args}}

[doc('Verify both build systems agree — run before pushing')]
verify: test spm-test

[doc('Regenerate Package.swift and every BUILD.bazel from scripts/modules.py')]
modules:
    python3 {{PROJECT_ROOT}}/scripts/modules.py

[doc('Build the combined DocC site for every library module into .build/docs (what the DocC workflow publishes)')]
docs:
    {{BAZEL}} build //:docs
    rm -rf {{PROJECT_ROOT}}/.build/docs && mkdir -p {{PROJECT_ROOT}}/.build
    cp -RL {{PROJECT_ROOT}}/bazel-bin/docs {{PROJECT_ROOT}}/.build/docs && chmod -R u+w {{PROJECT_ROOT}}/.build/docs

# mutation:begin
[doc('Mutation testing: plant the bugs in scripts/mutants/<Module>.py and check the tests catch each, e.g. just mutate Greetings, or just mutate Greetings --all')]
mutate module *args="":
    python3 {{PROJECT_ROOT}}/scripts/mutate.py {{module}} {{args}}
# mutation:end

# fuzz:begin
[doc('Fuzz with libFuzzer, time-boxed (a swift.org toolchain through swiftly; Fuzz/README.md), e.g. just fuzz, or just fuzz FuzzGreetings -t 600')]
fuzz *args="":
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py run {{args}}

[doc('Replay every fuzz corpus once, after a change')]
fuzz-regress *args="":
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py regress {{args}}

[doc('Replay and minimize one crash, e.g. just fuzz-repro FuzzGreetings Fuzz/Crashes/FuzzGreetings/crash-…')]
fuzz-repro target input:
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py repro {{target}} {{input}}
# fuzz:end

# differential:begin
[doc('Differential testing against reference implementations (Differential/README.md; needs uv), e.g. just diff, just diff --module Greetings, or just diff --cases 20000 --seed 7')]
diff *args="":
    python3 {{PROJECT_ROOT}}/scripts/differential.py {{args}}
# differential:end

# wasm:begin
[doc('SwiftPM tests on wasm32-wasi under wasmtime, a 32-bit Int, in groups of targets, e.g. just wasi-test, just wasi-test -c release, or just wasi-test --targets GreetingsTests')]
wasi-test *args="":
    python3 -u {{PROJECT_ROOT}}/scripts/wasi_test.py {{args}}
# wasm:end

# explore:begin
[doc('Build the browser explorer (Explore/) as size-optimized release WebAssembly into Explore/dist; EXPLORE_XCODE=/Applications/Xcode-<older>.app if the toolchain crashes on a newer SDK')]
explore:
    {{PROJECT_ROOT}}/Explore/build.sh
# explore:end

# benchmarks:begin
# The checkout of BenchmarkHarness whose benchmark-harness tool records simulated baselines.
BENCHMARK_HARNESS := env("BENCHMARK_HARNESS", home_directory() / "workspace" / "BenchmarkHarness")

[doc('Run the benchmarks, e.g. just bench, or just bench --target GreetingsBenchmarks')]
bench *args="":
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark {{args}}

[doc('Record the current results as the baseline named main')]
bench-baseline:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline update main

[doc('Compare the current results against the saved baseline')]
bench-compare:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline compare main

[doc("Record the benchmarks' simulated counts (Callgrind in a Linux VM; steady on a busy machine) as the simulated baseline, e.g. just bench-simulated, or just bench-simulated --target X")]
bench-simulated *args="": (_simulated-baseline "simulated" args)

[doc("Record simulated counts as simulated-current and compare them against the simulated baseline, e.g. just bench-simulated-compare --target X")]
bench-simulated-compare *args="": (_simulated-baseline "simulated-current" args)
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline compare simulated simulated-current {{args}}

[private]
_simulated-baseline name args:
    just --justfile {{BENCHMARK_HARNESS}}/justfile harness
    {{BENCHMARK_HARNESS}}/Harness/.build/release/benchmark-harness baseline update {{name}} --package-path {{PROJECT_ROOT}}/Benchmarks {{args}}
# benchmarks:end

# server:begin
[doc('Run the server on http://localhost:8080, e.g. just run, or just run routes')]
run *args="serve":
    # database:begin
    mkdir -p {{PROJECT_ROOT}}/.build
    DATABASE_PATH={{PROJECT_ROOT}}/.build/projectname.sqlite {{BAZEL}} run //Sources/ProjectNameServer -- {{args}}
    # database:end
    # !database:begin
    {{BAZEL}} run //Sources/ProjectNameServer -- {{args}}
    # !database:end

[doc('Build the production image and run it on http://localhost:8080')]
docker:
    docker build -t projectname {{PROJECT_ROOT}}
    # database:begin
    docker run --rm -p 8080:8080 -e DATABASE_PATH=/data/projectname.sqlite -v projectname-data:/data projectname
    # database:end
    # !database:begin
    docker run --rm -p 8080:8080 projectname
    # !database:end

[doc('Load-test the production image with k6 (brew install k6), e.g. just load, or just load --vus 5 --duration 10s; BASE_URL=… just load tests a running server instead')]
load *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${BASE_URL:-}" ]; then
        docker build -t projectname {{PROJECT_ROOT}}
        # database:begin
        container=$(docker run -d --rm -p 127.0.0.1::8080 -e DATABASE_PATH=/tmp/load.sqlite projectname)
        # database:end
        # !database:begin
        container=$(docker run -d --rm -p 127.0.0.1::8080 projectname)
        # !database:end
        trap 'docker stop "$container" >/dev/null' EXIT
        export BASE_URL="http://$(docker port "$container" 8080/tcp | head -n 1)"
        for _ in $(seq 60); do curl -fs "$BASE_URL/health" >/dev/null && break; sleep 1; done
        curl -fs "$BASE_URL/health" >/dev/null || { docker logs "$container"; echo "The server never answered /health" >&2; exit 1; }
    fi
    k6 run {{args}} {{PROJECT_ROOT}}/LoadTests/load.js
# server:end

# fly:begin
[doc('Deploy this checkout to Fly.io (the Release workflow deploys every push to main)')]
deploy:
    flyctl deploy --remote-only --ha=false
# fly:end

[doc('Generate an Xcode project from the Bazel graph and open it')]
generate *args="":
    @bash scripts/generate-xcodeproj.sh {{args}}

[doc('Build optimized: the library and the speed-reliant tests, not the debug-only test targets')]
release:
    {{BAZEL_RELEASE}} build --config=release //...

[doc('Store the BuildBuddy API key in the login Keychain (asks for it), once per Mac: every project from the template then builds with the remote cache (tools/bazel)')]
buildbuddy-key:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -s -p "BuildBuddy API key (hidden): " key
    echo
    if [ -z "$key" ]; then
        echo "No key entered; nothing stored" >&2
        exit 1
    fi
    # Through security's own command reader, so the key never appears in a process's arguments.
    printf 'add-generic-password -U -s buildbuddy -a api-key -l "BuildBuddy API key" -w %s\n' "$key" | security -i >/dev/null
    echo "Stored. Builds use BuildBuddy from the next Bazel command."

[doc('Set this repository’s BUILDBUDDY_API_KEY Actions secret from the Keychain with gh, so CI uses the remote cache too')]
ci-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! key="$(security find-generic-password -s buildbuddy -a api-key -w 2>/dev/null)"; then
        echo "No BuildBuddy API key in the Keychain; store it with just buildbuddy-key" >&2
        exit 1
    fi
    printf '%s' "$key" | gh secret set BUILDBUDDY_API_KEY

# The checkout of ProjectTemplate this project came from; .template.json records the commit.
PROJECT_TEMPLATE := env("PROJECT_TEMPLATE", home_directory() / "workspace" / "ProjectTemplate")

[doc('Merge the project template’s changes since .template.json’s commit into this checkout (needs a clean worktree), e.g. just template-update, or just template-update --to <commit>')]
template-update *args="":
    python3 {{PROJECT_TEMPLATE}}/template.py update {{PROJECT_ROOT}} {{args}}

[doc('Remove all build artifacts')]
clean:
    {{BAZEL}} clean
    {{BAZEL_RELEASE}} clean || true
    rm -rf {{PROJECT_ROOT}}/.build
    rm -rf {{PROJECT_ROOT}}/Benchmarks/.build # benchmarks:line
    rm -rf {{PROJECT_ROOT}}/Fuzz/.build # fuzz:line
    rm -rf {{PROJECT_ROOT}}/Differential/.build # differential:line
    rm -rf {{PROJECT_ROOT}}/Explore/.build {{PROJECT_ROOT}}/Explore/dist # explore:line

[doc('Print the dependency graph of a target')]
deps target="//Sources/ProjectName":
    {{BAZEL}} query 'deps({{target}})' --output=label_kind

[doc('List every buildable target')]
targets:
    {{BAZEL}} query '//...' --output=label_kind
