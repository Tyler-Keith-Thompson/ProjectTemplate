#!/usr/bin/env bash
# Start a new project from this template.
#
#   ./bootstrap.sh [options] <Name> [destination]
#
# Copies the template to <destination> (default ~/workspace/<Name>), renames every ProjectName /
# projectname token and path to <Name> / <name>, resolves dependencies and runs the tests.
#
# Options (anything not given is asked for when run from a terminal, and defaults to "no"
# otherwise; --yes takes the defaults without asking):
#   --type library|server|embedded|mcp|app
#                           A Swift package (default), a Vapor server with a Docker image,
#                           ESP32 firmware in Embedded Swift (ESP-IDF; needs swiftly), an MCP
#                           server over stdio, installed for Claude Code, or an iOS app in SwiftUI
#                           (view, snapshot and smoke tests in the simulator; lint).
#   --library, --server, --embedded, --mcp, --app
#                           Shorthands for --type.
#   --benchmarks            Include the Benchmarks/ package.
#   --mutation              Mutation testing: scripts/mutate.py and `just mutate <Module>`.
#   --fuzz                  libFuzzer targets in Fuzz/ and `just fuzz` (needs swiftly).
#   --differential          Differential testing against references: `just diff` (needs uv).
#   --wasm                  Library or embedded: test on wasm32-wasi under wasmtime (a 32-bit
#                           `Int`), `just wasi-test`.
#   --explore               Library only: a browser explorer (Explore/, `just explore`), published
#                           with the docs.
#   --views                 Library only: a SwiftUI view module for macOS and iOS, with ViewInspector
#                           view tests and snapshot tests on the Mac (`just record-snapshots`), and
#                           `just lint` (SwiftLint and a11y-check).
#   --examples              Library only: example apps in their own SwiftPM package (Examples/), a
#                           SwiftUI screen shared by iPhone and iPad, Mac, visionOS and watchOS apps
#                           that Bazel builds (`just example-*`, `just examples`), each with an Xcode
#                           scheme.
#   --ios                   Library or server: an iOS app (Apps/<Name>, `just run` or, for a
#                           server, `just run-app`) and what iOS modules and simulator tests need
#                           (tools/test_host, the simulator settings in .bazelrc, tools/ios.bzl).
#   --simulator             Library or server: what simulator tests need (tools/test_host, the
#                           simulator settings in .bazelrc, tools/ios.bzl), without an app. --ios
#                           brings it too.
#   --fly                   Server only: deploy to Fly.io (fly.toml; with CI, a deploy job in
#                           Release deploys every push to main, else `just deploy` only).
#   --database              Server only: SQLite through Fluent. With --fly, Litestream replicates
#                           it to object storage and restores it on a new volume.
#   --trunk                 With CI: pull requests merge through Trunk's merge queue
#                           (.trunk/trunk.yaml names the checks it waits for), not pushes to main.
#   --no-ci                 No GitHub Actions workflows (.github/workflows): no CI, releases,
#                           published docs or explorer, or deploys on push. CI is on by default
#                           (--ci), and the only option asked as [Y/n]. The app type has none: the
#                           workflows run in Linux containers, and its tests need a Mac.
#   --no-benchmarks, --no-mutation, --no-fuzz,
#                           --no-differential, --no-wasm, --no-explore, --no-views, --no-examples, --no-ios, --no-simulator, --no-fly,
#                           --no-database, --no-trunk
#   --yes, -y               Ask nothing.
#   --render-only           Copy, rename and keep or drop the optional sections, then stop: no
#                           generated files, git, stamp or tests. template.py renders with it.
#
# The template is the library type in place. The server, embedded, mcp and app types add
# templates/<type>/ on top, --views adds templates/views/, --examples templates/examples/, --ios
# templates/ios/, the app type, --ios and --simulator templates/simulator/, and CI adds templates/ci/: the GitHub Actions workflows, kept there so
# the template repository runs none of them. Each optional piece keeps or drops the sections marked
# for it (.github/docs/working-on-the-template.md, "Optional pieces").
set -euo pipefail

usage() {
    sed -n '3,54p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit "${1:-1}"
}

TYPE=""
BENCHMARKS=""
MUTATION=""
FUZZ=""
DIFFERENTIAL=""
WASM=""
EXPLORE=""
VIEWS=""
EXAMPLES=""
IOS=""
SIMULATOR_OPTION=""
FLY=""
DATABASE=""
CI=""
TRUNK=""
ASK=true
RENDER_ONLY=false
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --type) [ $# -ge 2 ] || usage; TYPE="$2"; shift ;;
        --type=*) TYPE="${1#--type=}" ;;
        --library) TYPE=library ;;
        --server) TYPE=server ;;
        --embedded) TYPE=embedded ;;
        --mcp) TYPE=mcp ;;
        --app) TYPE=app ;;
        --benchmarks) BENCHMARKS=true ;;
        --no-benchmarks) BENCHMARKS=false ;;
        --mutation) MUTATION=true ;;
        --no-mutation) MUTATION=false ;;
        --fuzz) FUZZ=true ;;
        --no-fuzz) FUZZ=false ;;
        --differential) DIFFERENTIAL=true ;;
        --no-differential) DIFFERENTIAL=false ;;
        --wasm) WASM=true ;;
        --no-wasm) WASM=false ;;
        --explore) EXPLORE=true ;;
        --no-explore) EXPLORE=false ;;
        --views) VIEWS=true ;;
        --no-views) VIEWS=false ;;
        --examples) EXAMPLES=true ;;
        --no-examples) EXAMPLES=false ;;
        --ios) IOS=true ;;
        --no-ios) IOS=false ;;
        --simulator) SIMULATOR_OPTION=true ;;
        --no-simulator) SIMULATOR_OPTION=false ;;
        --fly) FLY=true ;;
        --no-fly) FLY=false ;;
        --database) DATABASE=true ;;
        --no-database) DATABASE=false ;;
        --trunk) TRUNK=true ;;
        --no-trunk) TRUNK=false ;;
        --ci) CI=true ;;
        --no-ci) CI=false ;;
        -y|--yes) ASK=false ;;
        --render-only) RENDER_ONLY=true; ASK=false ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) POSITIONAL+=("$1") ;;
    esac
    shift
done
if [ ${#POSITIONAL[@]} -lt 1 ] || [ ${#POSITIONAL[@]} -gt 2 ]; then
    usage
fi

NAME="${POSITIONAL[0]}"
DEST="${POSITIONAL[1]:-$HOME/workspace/$NAME}"
LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)"

if ! [[ "$NAME" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    echo "The name must be an UpperCamelCase identifier (a Swift module name): $NAME" >&2
    exit 1
fi
if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    echo "Destination is not empty: $DEST" >&2
    exit 1
fi

# Questions go to the terminal, so they work even when stdout is piped.
if [ "$ASK" = true ] && ! { : < /dev/tty; } 2>/dev/null; then
    ASK=false
fi

ask_yes_no() {  # ask_yes_no <question>; prints true or false
    local answer
    while true; do
        printf '%s [y/N] ' "$1" > /dev/tty
        read -r answer < /dev/tty
        case "$answer" in
            [yY]|[yY][eE][sS]) echo true; return ;;
            ""|[nN]|[nN][oO]) echo false; return ;;
        esac
    done
}

if [ -z "$TYPE" ]; then
    if [ "$ASK" = true ]; then
        {
            echo "Project type:"
            echo "  1) library  A Swift package: Bazel for development, SwiftPM published"
            echo "  2) server   A Vapor server and its Docker image; optionally Fly.io and SQLite"
            echo "  3) embedded ESP32 firmware in Embedded Swift: modules tested on the Mac, built for the chip"
            echo "  4) mcp      An MCP server over stdio: typed tools, installed for Claude Code"
            echo "  5) app      An iOS app in SwiftUI: view, snapshot and smoke tests in the simulator"
        } > /dev/tty
        while [ -z "$TYPE" ]; do
            printf 'Choose [1]: ' > /dev/tty
            read -r choice < /dev/tty
            case "$choice" in
                ""|1|library) TYPE=library ;;
                2|server) TYPE=server ;;
                3|embedded) TYPE=embedded ;;
                4|mcp) TYPE=mcp ;;
                5|app) TYPE=app ;;
            esac
        done
    else
        TYPE=library
    fi
fi
case "$TYPE" in
    library|server|embedded|mcp|app) ;;
    *) echo "Unknown type: $TYPE (library, server, embedded, mcp or app)" >&2; exit 1 ;;
esac
if [ "$TYPE" != server ] && { [ "$FLY" = true ] || [ "$DATABASE" = true ]; }; then
    echo "--fly and --database apply to the server type only" >&2
    exit 1
fi
if { [ "$TYPE" = server ] || [ "$TYPE" = mcp ] || [ "$TYPE" = app ]; } && [ "$WASM" = true ]; then
    echo "--wasm applies to the library and embedded types only" >&2
    exit 1
fi
if [ "$TYPE" != library ] && [ "$EXPLORE" = true ]; then
    echo "--explore applies to the library type only" >&2
    exit 1
fi
if [ "$TYPE" != library ] && [ "$VIEWS" = true ]; then
    echo "--views applies to the library type only (the app type has its own views and tests)" >&2
    exit 1
fi
if [ "$TYPE" != library ] && [ "$EXAMPLES" = true ]; then
    echo "--examples applies to the library type only" >&2
    exit 1
fi
if { [ "$TYPE" != library ] && [ "$TYPE" != server ]; } && [ "$IOS" = true ]; then
    echo "--ios applies to the library and server types only (the app type is an iOS app already)" >&2
    exit 1
fi
if { [ "$TYPE" != library ] && [ "$TYPE" != server ]; } && [ "$SIMULATOR_OPTION" = true ]; then
    echo "--simulator applies to the library and server types only (the app type has the simulator already)" >&2
    exit 1
fi
if [ "$TYPE" = app ]; then
    if [ "$CI" = true ] || [ "$TRUNK" = true ]; then
        echo "The app type has no CI (--ci, --trunk): the workflows run in Linux containers, and its tests need a Mac" >&2
        exit 1
    fi
    CI=false
fi

ask_unset() {  # ask_unset <current value> <question>; prints the value, asking when unset
    if [ -n "$1" ]; then echo "$1"
    elif [ "$ASK" = true ]; then ask_yes_no "$2"
    else echo false
    fi
}
ask_unset_yes() {  # ask_unset_yes <current value> <question>; like ask_unset, but "yes" by default
    local answer
    if [ -n "$1" ]; then echo "$1"; return; fi
    if [ "$ASK" = false ]; then echo true; return; fi
    while true; do
        printf '%s [Y/n] ' "$2" > /dev/tty
        read -r answer < /dev/tty
        case "$answer" in
            ""|[yY]|[yY][eE][sS]) echo true; return ;;
            [nN]|[nN][oO]) echo false; return ;;
        esac
    done
}
ask_simulator() {  # --simulator, asked only without --ios, which brings the simulator piece already
    if [ "$IOS" = true ]; then
        [ -n "$SIMULATOR_OPTION" ] || SIMULATOR_OPTION=false
    else
        SIMULATOR_OPTION="$(ask_unset "$SIMULATOR_OPTION" "Tests in the iOS simulator, without an app?")"
    fi
}
CI="$(ask_unset_yes "$CI" "GitHub Actions (CI, releases, published docs)?")"
if [ "$CI" = true ]; then
    TRUNK="$(ask_unset "$TRUNK" "Merge pull requests through Trunk's merge queue?")"
elif [ "$TRUNK" = true ]; then
    echo "--trunk needs CI: the merge queue waits for CI's checks" >&2
    exit 1
else
    TRUNK=false
fi
if [ "$TYPE" = server ]; then
    FLY="$(ask_unset "$FLY" "Deploy to Fly.io?")"
    if [ "$FLY" = true ]; then
        DATABASE="$(ask_unset "$DATABASE" "SQLite database (replicated with Litestream)?")"
    else
        DATABASE="$(ask_unset "$DATABASE" "SQLite database?")"
    fi
    WASM=false
    EXPLORE=false
    VIEWS=false
    EXAMPLES=false
    IOS="$(ask_unset "$IOS" "An iOS app (and iOS modules tested in the simulator)?")"
    ask_simulator
elif [ "$TYPE" = embedded ]; then
    FLY=false
    DATABASE=false
    EXPLORE=false
    VIEWS=false
    EXAMPLES=false
    IOS=false
    WASM="$(ask_unset "$WASM" "Tests on WebAssembly (wasm32-wasi, a 32-bit Int like the chip's)?")"
elif [ "$TYPE" = mcp ] || [ "$TYPE" = app ]; then
    FLY=false
    DATABASE=false
    WASM=false
    EXPLORE=false
    VIEWS=false
    EXAMPLES=false
    IOS=false
else
    FLY=false
    DATABASE=false
    WASM="$(ask_unset "$WASM" "Tests on WebAssembly (wasm32-wasi)?")"
    EXPLORE="$(ask_unset "$EXPLORE" "A browser explorer?")"
    VIEWS="$(ask_unset "$VIEWS" "SwiftUI views (view and snapshot tests, lint)?")"
    EXAMPLES="$(ask_unset "$EXAMPLES" "Example apps for iOS, macOS, visionOS and watchOS?")"
    IOS="$(ask_unset "$IOS" "An iOS app (and iOS modules tested in the simulator)?")"
    ask_simulator
fi
# Only the library and server types take --simulator; elsewhere the type decides.
[ -n "$SIMULATOR_OPTION" ] || SIMULATOR_OPTION=false
BENCHMARKS="$(ask_unset "$BENCHMARKS" "Benchmarks package?")"
MUTATION="$(ask_unset "$MUTATION" "Mutation testing?")"
FUZZ="$(ask_unset "$FUZZ" "Fuzzing with libFuzzer?")"
DIFFERENTIAL="$(ask_unset "$DIFFERENTIAL" "Differential testing?")"

LIBRARY=false
SERVER=false
EMBEDDED=false
MCP=false
APP=false
[ "$TYPE" = library ] && LIBRARY=true
[ "$TYPE" = server ] && SERVER=true
[ "$TYPE" = embedded ] && EMBEDDED=true
[ "$TYPE" = mcp ] && MCP=true
[ "$TYPE" = app ] && APP=true
LITESTREAM=false
[ "$FLY" = true ] && [ "$DATABASE" = true ] && LITESTREAM=true
# What the app type and --views share: SwiftLint and a11y-check (`just lint`), and the packages
# view and snapshot tests use.
SWIFTUI=false
{ [ "$APP" = true ] || [ "$VIEWS" = true ]; } && SWIFTUI=true
# Whatever builds the package for wasm32-wasi: the WebAssembly tests and the explorer. It keeps
# NON_WASI_PACKAGES, the packages whose products every platform but WASI links.
WASI=false
{ [ "$WASM" = true ] || [ "$EXPLORE" = true ]; } && WASI=true
# What the app type, --ios and --simulator share: iOS modules (tools/ios.bzl), tests in the
# simulator (tools/test_host) and the simulator settings in .bazelrc.
SIMULATOR=false
{ [ "$APP" = true ] || [ "$IOS" = true ] || [ "$SIMULATOR_OPTION" = true ]; } && SIMULATOR=true

if [ "$RENDER_ONLY" = false ]; then
    echo "Creating $NAME ($TYPE; benchmarks: $BENCHMARKS, mutation: $MUTATION, fuzz: $FUZZ, differential: $DIFFERENTIAL, wasm: $WASM, explore: $EXPLORE, views: $VIEWS, examples: $EXAMPLES, ios: $IOS, simulator: $SIMULATOR_OPTION, fly: $FLY, database: $DATABASE, ci: $CI, trunk: $TRUNK) at $DEST"
fi

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

# copy_template <directory> <rsync option>...: the template's <directory> ("" for its root) into
# the project. In a git checkout of its own, whatever git ignores there stays behind too (the
# checkout's .gitignore, .git/info/exclude and the global excludes file), so local tool state (another
# tool's clones and worktrees, build output, caches) never reaches a project, whatever its name,
# while an untracked file git doesn't ignore (a template edit not yet added) still renders.
# Elsewhere (template.py renders from an archive, which has no .git) the excludes alone keep
# things out. Rejected: copying only `git ls-files` through --files-from (rsync then checks each
# listed file against the excludes, so a directory pattern such as /templates no longer covers what
# is under it, and every exclude would need rewriting); naming each tool's directory (the next
# tool's breaks a project the same way).
TEMPLATE_IS_CHECKOUT=false
if [ "$(git -C "$TEMPLATE" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$TEMPLATE" && pwd -P)" ]; then
    TEMPLATE_IS_CHECKOUT=true
fi
copy_template() {
    local prefix="${1:+$1/}"
    shift
    if [ "$TEMPLATE_IS_CHECKOUT" = false ]; then
        rsync -a "$TEMPLATE/$prefix" "$DEST/" "$@"
        return
    fi
    # Each ignored path (a directory once, as path/), anchored at the copied directory.
    git -C "$TEMPLATE" ls-files -z --others --ignored --exclude-standard --directory -- "${prefix:-.}" |
        while IFS= read -r -d '' path; do
            printf '/%s\0' "${path#"$prefix"}"
        done |
        rsync -a --from0 --exclude-from=- "$TEMPLATE/$prefix" "$DEST/" "$@"
}

# Everything but the template's own scaffolding and build output.
EXTRA_EXCLUDES=()
if [ "$BENCHMARKS" = false ]; then
    EXTRA_EXCLUDES+=(--exclude '/Benchmarks')
fi
copy_template "" ${EXTRA_EXCLUDES[@]+"${EXTRA_EXCLUDES[@]}"} \
    --exclude '.git' --exclude 'bazel-*' --exclude '.build' --exclude '.swiftpm' \
    --exclude 'Benchmarks/.build' --exclude 'swift/.build' --exclude '__pycache__' \
    --exclude 'bootstrap.sh' --exclude 'template.py' --exclude '/template_test.py' --exclude '/.github/README.md' --exclude '/.github/docs' --exclude 'user.bazelrc' --exclude '/templates' --exclude '/ci-image' \
    --exclude '.claude/worktrees' --exclude '/.kanban' --exclude '/Fuzz/Corpus' --exclude '/Fuzz/Crashes' --exclude '/Differential/Failures' --exclude '/Explore/dist' --exclude '*.xcodeproj' --exclude '/xcode' --exclude '.DS_Store'
if [ "$SERVER" = true ]; then
    copy_template templates/server --exclude '.DS_Store'
fi
if [ "$EMBEDDED" = true ]; then
    copy_template templates/embedded --exclude '.DS_Store' \
        --exclude '/Firmware/build' --exclude '/Firmware/managed_components' --exclude '/Firmware/sdkconfig' --exclude '/Firmware/sdkconfig.old'
fi
if [ "$MCP" = true ]; then
    copy_template templates/mcp --exclude '.DS_Store'
fi
if [ "$APP" = true ]; then
    copy_template templates/app --exclude '.DS_Store'
fi
if [ "$SIMULATOR" = true ]; then
    copy_template templates/simulator --exclude '.DS_Store'
fi
if [ "$IOS" = true ]; then
    copy_template templates/ios --exclude '.DS_Store'
fi
if [ "$VIEWS" = true ]; then
    copy_template templates/views --exclude '.DS_Store'
fi
if [ "$EXAMPLES" = true ]; then
    copy_template templates/examples --exclude '.DS_Store' --exclude '.build' --exclude '.swiftpm'
fi
# The workflows live outside .github/workflows here, so the template repository runs none itself.
if [ "$CI" = true ]; then
    copy_template templates/ci --exclude '.DS_Store'
fi

# Whole files and directories that belong to one optional piece.
remove_unless() {  # remove_unless <enabled> <path>...
    local enabled="$1"; shift
    if [ "$enabled" = false ]; then
        for path in "$@"; do rm -rf "${DEST:?}/$path"; done
    fi
}
remove_unless "$LIBRARY" Tests/ProjectNameTests
remove_unless "$BENCHMARKS" tools/benchmarks.bzl scripts/bench_simulated.py
remove_unless "$MUTATION" scripts/mutate.py scripts/mutants
remove_unless "$FUZZ" Fuzz scripts/fuzz.py
remove_unless "$WASM" scripts/wasi_test.py
remove_unless "$EXPLORE" Explore
remove_unless "$SWIFTUI" tools/lint.bzl third_party .swiftlint.yml .swiftlint-tests.yml
remove_unless "$DIFFERENTIAL" Differential scripts/differential.py scripts/differential_greetings.py
remove_unless "$FLY" fly.toml
remove_unless "$DATABASE" Sources/App/Database
remove_unless "$LITESTREAM" litestream.yml scripts/docker-entrypoint.sh
remove_unless "$CI" .github
remove_unless "$TRUNK" .trunk

# Paths first, deepest first, so a renamed directory's children are already renamed.
find "$DEST" -depth -name '*ProjectName*' -not -path "$DEST/.git/*" | while IFS= read -r path; do
    mv "$path" "$(dirname "$path")/$(basename "$path" | sed "s/ProjectName/$NAME/g")"
done

# Then file contents (text files only).
find "$DEST" -type f -not -path "$DEST/.git/*" | while IFS= read -r file; do
    if file --mime "$file" | grep -q 'charset=binary'; then continue; fi
    if grep -q 'ProjectName\|projectname' "$file"; then
        sed -i '' -e "s/ProjectName/$NAME/g" -e "s/projectname/$LOWER/g" "$file"
    fi
done

# Optional sections: keep or drop what the template marks, and remove the markers either way.
#
#   <comment> feature:begin / <comment> feature:end   a block, kept when the feature is on
#   <comment> !feature:begin / ... !feature:end       a block, kept when it is off
#   ... # feature:line, ... // feature:line           one line (also `<!-- feature:line -->`
#                                                       anywhere in the line)
#   #| code, //| code                                 a dormant line inside a block or on a
#                                                       marked line: commented out in the template,
#                                                       uncommented when kept; anywhere else
#                                                       it stops the render, naming file and line
#
# <comment> is #, // or <!--. Blocks nest; a line is kept when every enclosing block is.
python3 - "$DEST" "benchmarks=$BENCHMARKS" "mutation=$MUTATION" "fuzz=$FUZZ" "differential=$DIFFERENTIAL" "wasm=$WASM" "explore=$EXPLORE" "views=$VIEWS" "examples=$EXAMPLES" "ios=$IOS" "simulator=$SIMULATOR" "swiftui=$SWIFTUI" "wasi=$WASI" "library=$LIBRARY" "server=$SERVER" "embedded=$EMBEDDED" "mcp=$MCP" "app=$APP" "fly=$FLY" \
    "database=$DATABASE" "litestream=$LITESTREAM" "ci=$CI" "trunk=$TRUNK" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
features = {k: v == "true" for k, v in (arg.split("=") for arg in sys.argv[2:])}
names = "|".join(features)
block = re.compile(rf"^\s*(?:#|//|<!--)\s*(!?)({names}):(begin|end)\b")
line_marker = re.compile(rf"\s*(?:(?:#|//)\s*(!?)({names}):line\s*$|<!--\s*(!?)({names}):line\s*-->)")
dormant = re.compile(r"^(\s*)(?:#|//)\| ?")
anywhere = re.compile(rf"(?:#|//|<!--)\s*!?(?:{names}):(?:begin|end|line)\b")

REMOVED = "\x00\n"  # stands in for a dropped line until blank lines around it are merged


def on(negated, name):
    return features[name] != (negated == "!")

for path in sorted(p for p in root.rglob("*") if p.is_file() and ".git" not in p.parts):
    try:
        text = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    out, stack, changed = [], [], False
    if not anywhere.search(text):
        stray = next((n for n, l in enumerate(text.splitlines(), 1) if dormant.match(l)), None)
        if stray:
            sys.exit(f"{path.relative_to(root)}:{stray}: a dormant '#|' or '//|' line outside any block and without a line marker")
        continue
    for number, line in enumerate(text.splitlines(keepends=True), 1):
        match = block.match(line)
        if match:
            changed = True
            out.append(REMOVED)
            negated, name, kind = match.groups()
            if kind == "begin":
                stack.append((negated + name, on(negated, name)))
            else:
                assert stack and stack[-1][0] == negated + name, f"{path}:{number}: unmatched {negated}{name}:end"
                stack.pop()
            continue
        keep = all(kept for _, kept in stack)
        # A line may carry several markers (`<!-- explore:line --><!-- ci:line -->`): kept when all hold.
        marked = list(line_marker.finditer(line))
        if marked:
            changed = True
            for marker in marked:
                negated, name = (marker.group(1), marker.group(2)) if marker.group(2) else (marker.group(3), marker.group(4))
                keep = keep and on(negated, name)
            ending = "\n" if line.endswith("\n") else ""
            line = line_marker.sub("", line.rstrip("\n")) + ending
        # A dormant line nothing switches on would ship with its marker in every variant.
        if not stack and not marked and dormant.match(line):
            sys.exit(f"{path.relative_to(root)}:{number}: a dormant '#|' or '//|' line outside any block and without a line marker")
        if not keep:
            out.append(REMOVED)
            continue
        if (stack or marked) and dormant.match(line):
            line = dormant.sub(r"\1", line, count=1)
        out.append(line)
    assert not stack, f"{path}: {stack[-1][0]}:begin without an end"
    if changed:
        # Where removed lines sat between two blank lines, keep one blank line. Repeated, so that
        # neighboring removed blocks, each with its own blank line after it, leave just one.
        text, merged = "".join(out), None
        while merged != text:
            merged, text = text, re.sub(r"\n\n(?:\x00\n)+\n", "\n\n", text)
        path.write_text(text.replace(REMOVED, ""))
PY

if [ "$RENDER_ONLY" = true ]; then
    exit 0
fi

# The stamp: which template commit and options made this project, so template.py can merge later
# template changes into it (.github/docs/updating.md).
if COMMIT="$(git -C "$TEMPLATE" rev-parse --verify HEAD 2>/dev/null)"; then
    MODIFIED=false
    # A tracked change, or an untracked file the copy brought along, makes the project differ from
    # the stamped commit. An untracked file the copy leaves out (the board's .kanban/, say) doesn't.
    UNTRACKED_COPIED=false
    while IFS= read -r untracked; do
        relative="${untracked#templates/*/}"
        if [ -e "$DEST/$untracked" ] || [ -e "$DEST/$relative" ]; then
            UNTRACKED_COPIED=true
            break
        fi
    done < <(git -C "$TEMPLATE" ls-files --others --exclude-standard)
    if [ -n "$(git -C "$TEMPLATE" status --porcelain --untracked-files=no)" ] || [ "$UNTRACKED_COPIED" = true ]; then
        MODIFIED=true
        echo "Note: the template has uncommitted changes, so the stamp in .template.json is approximate." >&2
    fi
    python3 - "$DEST/.template.json" "$COMMIT" "$NAME" "$TYPE" "$BENCHMARKS" "$MUTATION" "$FUZZ" "$DIFFERENTIAL" "$WASM" "$EXPLORE" "$VIEWS" "$EXAMPLES" "$IOS" "$SIMULATOR_OPTION" "$FLY" "$DATABASE" "$CI" "$TRUNK" "$MODIFIED" <<'PY'
import json, sys

path, commit, name, kind, benchmarks, mutation, fuzz, differential, wasm, explore, views, examples, ios, simulator, fly, database, ci, trunk, modified = sys.argv[1:]
stamp = {"commit": commit, "name": name, "type": kind, "benchmarks": benchmarks == "true",
         "mutation": mutation == "true", "fuzz": fuzz == "true",
         "differential": differential == "true", "wasm": wasm == "true",
         "explore": explore == "true", "views": views == "true", "examples": examples == "true", "ios": ios == "true", "simulator": simulator == "true", "fly": fly == "true", "database": database == "true",
         "ci": ci == "true", "trunk": trunk == "true"}
if modified == "true":
    stamp["modified"] = True
with open(path, "w") as file:
    file.write(json.dumps(stamp, indent=2) + "\n")
PY
else
    echo "Note: the template is not a git checkout, so the project gets no .template.json stamp." >&2
fi

cd "$DEST"
python3 scripts/modules.py
if [ ! -d .git ]; then
    git init -q -b main
fi

echo "Resolving dependencies and running the tests..."
just resolve >/dev/null
just test

STEP=3
next() { echo "  $STEP. $1"; STEP=$((STEP + 1)); }
echo
echo "$NAME is ready at $DEST."
echo
echo "Next:"
echo "  1. Fill in the <placeholders> in README.md, AGENTS.md, BUILD.bazel's first line and"
echo "     Sources/$NAME/$NAME.docc/$NAME.md."
if [ "$SERVER" = true ]; then
    echo "  2. Replace the examples: the routes in Sources/App, and the Greetings module (add your"
    echo "     first module to MODULES in scripts/modules.py, remove the Greetings rows, \`just modules\`)."
elif [ "$MCP" = true ]; then
    echo "  2. Replace the examples: the greet tool in Sources/Tools, and the Greetings module (add your"
    echo "     first module to MODULES in scripts/modules.py, remove the Greetings rows, \`just modules\`)."
elif [ "$APP" = true ]; then
    echo "  2. Replace the examples: the greeting screen (GreetingFeature), its service (GreetingService) and"
    echo "     the Greetings module (rows in MODULES, IOS_MODULES and TEST_TARGETS in scripts/modules.py,"
    echo "     then \`just modules\`). \`just run\` launches the app in the simulator; \`just record-snapshots\`"
    echo "     re-records the snapshots after a change to how a screen looks."
elif [ "$EMBEDDED" = true ]; then
    echo "  2. Replace the examples: Firmware/main/Main.swift, and the Greetings module (add your first"
    echo "     module to MODULES and FIRMWARE_MODULES in scripts/modules.py, remove the Greetings rows,"
    echo "     \`just modules\`). The chip is Firmware/sdkconfig.defaults' (ESP32-C6); \`just firmware\`"
    echo "     builds the image and \`just flash\` flashes it (ESP-IDF 5.5 in ~/esp/esp-idf or IDF_PATH)."
elif [ "$VIEWS" = true ]; then
    echo "  2. Replace the examples: the Greetings module and its view module, GreetingsUI (rows in"
    echo "     MODULES and TEST_TARGETS in scripts/modules.py, then \`just modules\`). \`just record-snapshots\`"
    echo "     re-records the snapshots after a change to how a view looks."
else
    echo "  2. Replace the Greetings example: add your first module to MODULES in scripts/modules.py,"
    echo "     remove the Greetings rows and directories, run \`just modules\`."
fi
if [ "$IOS" = true ]; then
    if [ "$SERVER" = true ]; then RUN_APP="just run-app"; else RUN_APP="just run"; fi
    next "The iOS app, Apps/$NAME: \`$RUN_APP\` launches it in the simulator. Its screens go in modules listed"
    echo "     in IOS_MODULES (scripts/modules.py), whose tests run in the simulator."
fi
if [ "$SIMULATOR_OPTION" = true ] && [ "$IOS" = false ]; then
    next "Tests in the iOS simulator: list a test target in SIMULATOR_TESTS (scripts/modules.py), then"
    echo "     \`just modules\`; \`just test\` runs it inside tools/test_host on a Mac."
fi
next "git add -A && git commit -m \"[main] - $NAME from the project template\""
if [ "$MCP" = true ]; then
    next "\`just install\` builds the server optimized into ~/.local/bin/$LOWER-mcp; then"
    echo "     \`claude mcp add $LOWER -- ~/.local/bin/$LOWER-mcp\` registers it with Claude Code."
fi
if [ "$CI" = true ]; then
    next "On GitHub: set Pages to deploy from gh-pages. For the remote cache in CI, once the repository"
    echo "     exists: \`just ci-secrets\` (the BuildBuddy key, from the Keychain; \`just buildbuddy-key\` stores"
    echo "     it once per Mac, and local builds then use the cache too)."
    next "CI's Bazel jobs pull the private ghcr.io/tyler-keith-thompson/swift-bazel image: add the"
    echo "     repository under Manage Actions access in the package's settings (Read), or CI can't start"
    echo "     (github.com/users/Tyler-Keith-Thompson/packages/container/package/swift-bazel/settings)."
fi
if [ "$TRUNK" = true ]; then
    next "Trunk: install Trunk's GitHub app on the repository and turn on its merge queue for main"
    echo "     (app.trunk.io). Branch protection on main should require \`ci / Bazel tests\` and"
    echo "     \`ci / SwiftPM tests\`, so a pull request merges only through the queue."
fi
if [ "$FLY" = true ] && [ "$CI" = true ]; then
    next "Fly.io: \`fly launch --no-deploy --copy-config --name $LOWER\` (app names are global; if"
    echo "     $LOWER is taken, change \`app\` in fly.toml), then add a FLY_API_TOKEN secret on GitHub"
    echo "     from \`fly tokens create deploy\`. Every push to main deploys."
elif [ "$FLY" = true ]; then
    next "Fly.io: \`fly launch --no-deploy --copy-config --name $LOWER\` (app names are global; if"
    echo "     $LOWER is taken, change \`app\` in fly.toml). \`just deploy\` deploys."
fi
if [ "$DATABASE" = true ] && [ "$FLY" = true ]; then
    next "The volume: \`fly volumes create data --size 1 --region den\`."
fi
if [ "$LITESTREAM" = true ]; then
    next "Litestream: create a B2 bucket and application key, then"
    echo "     \`fly secrets set B2_KEY_ID=… B2_APPLICATION_KEY=… B2_BUCKET_NAME=… B2_ENDPOINT=https://s3.<region>.backblazeb2.com\`."
    echo "     Until B2_BUCKET_NAME is set the server runs without replication."
fi
