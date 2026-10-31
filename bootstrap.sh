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
#   --type library|server   A Swift package (default), or a Vapor server with a Docker image.
#   --library, --server     Shorthands for --type.
#   --benchmarks            Include the Benchmarks/ package.
#   --fly                   Server only: deploy to Fly.io (fly.toml and a deploy job in Release).
#   --database              Server only: SQLite through Fluent. With --fly, Litestream replicates
#                           it to object storage and restores it on a new volume.
#   --no-benchmarks, --no-fly, --no-database
#   --yes, -y               Ask nothing.
#   --render-only           Copy, rename and keep or drop the optional sections, then stop: no
#                           generated files, git, stamp or tests. template.py renders with it.
#
# The template is the library type in place. The server type adds templates/server/ on top, and
# each optional piece keeps or drops the sections marked for it (TEMPLATE.md, "Optional pieces").
set -euo pipefail

usage() {
    sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit "${1:-1}"
}

TYPE=""
BENCHMARKS=""
FLY=""
DATABASE=""
ASK=true
RENDER_ONLY=false
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --type) [ $# -ge 2 ] || usage; TYPE="$2"; shift ;;
        --type=*) TYPE="${1#--type=}" ;;
        --library) TYPE=library ;;
        --server) TYPE=server ;;
        --benchmarks) BENCHMARKS=true ;;
        --no-benchmarks) BENCHMARKS=false ;;
        --fly) FLY=true ;;
        --no-fly) FLY=false ;;
        --database) DATABASE=true ;;
        --no-database) DATABASE=false ;;
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
        } > /dev/tty
        while [ -z "$TYPE" ]; do
            printf 'Choose [1]: ' > /dev/tty
            read -r choice < /dev/tty
            case "$choice" in
                ""|1|library) TYPE=library ;;
                2|server) TYPE=server ;;
            esac
        done
    else
        TYPE=library
    fi
fi
case "$TYPE" in
    library|server) ;;
    *) echo "Unknown type: $TYPE (library or server)" >&2; exit 1 ;;
esac
if [ "$TYPE" = library ] && { [ "$FLY" = true ] || [ "$DATABASE" = true ]; }; then
    echo "--fly and --database apply to the server type only" >&2
    exit 1
fi

ask_unset() {  # ask_unset <current value> <question>; prints the value, asking when unset
    if [ -n "$1" ]; then echo "$1"
    elif [ "$ASK" = true ]; then ask_yes_no "$2"
    else echo false
    fi
}
if [ "$TYPE" = server ]; then
    FLY="$(ask_unset "$FLY" "Deploy to Fly.io?")"
    if [ "$FLY" = true ]; then
        DATABASE="$(ask_unset "$DATABASE" "SQLite database (replicated with Litestream)?")"
    else
        DATABASE="$(ask_unset "$DATABASE" "SQLite database?")"
    fi
else
    FLY=false
    DATABASE=false
fi
BENCHMARKS="$(ask_unset "$BENCHMARKS" "Benchmarks package?")"

LIBRARY=false
SERVER=false
[ "$TYPE" = library ] && LIBRARY=true
[ "$TYPE" = server ] && SERVER=true
LITESTREAM=false
[ "$FLY" = true ] && [ "$DATABASE" = true ] && LITESTREAM=true

if [ "$RENDER_ONLY" = false ]; then
    echo "Creating $NAME ($TYPE; benchmarks: $BENCHMARKS, fly: $FLY, database: $DATABASE) at $DEST"
fi

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

# Everything but the template's own scaffolding and build output.
EXTRA_EXCLUDES=()
if [ "$BENCHMARKS" = false ]; then
    EXTRA_EXCLUDES+=(--exclude '/Benchmarks')
fi
rsync -a "$TEMPLATE/" "$DEST/" ${EXTRA_EXCLUDES[@]+"${EXTRA_EXCLUDES[@]}"} \
    --exclude '.git' --exclude 'bazel-*' --exclude '.build' --exclude '.swiftpm' \
    --exclude 'Benchmarks/.build' --exclude 'swift/.build' --exclude '__pycache__' \
    --exclude 'bootstrap.sh' --exclude 'template.py' --exclude 'TEMPLATE.md' --exclude 'user.bazelrc' --exclude '/templates' \
    --exclude '.claude/worktrees' --exclude '*.xcodeproj' --exclude '.DS_Store'
if [ "$SERVER" = true ]; then
    rsync -a "$TEMPLATE/templates/server/" "$DEST/" --exclude '.DS_Store'
fi

# Whole files and directories that belong to one optional piece.
remove_unless() {  # remove_unless <enabled> <path>...
    local enabled="$1"; shift
    if [ "$enabled" = false ]; then
        for path in "$@"; do rm -rf "${DEST:?}/$path"; done
    fi
}
remove_unless "$LIBRARY" Tests/ProjectNameTests
remove_unless "$FLY" fly.toml
remove_unless "$DATABASE" Sources/App/Database
remove_unless "$LITESTREAM" litestream.yml scripts/docker-entrypoint.sh

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
#                                                       uncommented when kept
#
# <comment> is #, // or <!--. Blocks nest; a line is kept when every enclosing block is.
python3 - "$DEST" "benchmarks=$BENCHMARKS" "library=$LIBRARY" "server=$SERVER" "fly=$FLY" \
    "database=$DATABASE" "litestream=$LITESTREAM" <<'PY'
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
    if not anywhere.search(text):
        continue
    out, stack, changed = [], [], False
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
        marked = line_marker.search(line)
        if marked:
            changed = True
            negated, name = (marked.group(1), marked.group(2)) if marked.group(2) else (marked.group(3), marked.group(4))
            keep = keep and on(negated, name)
            ending = "\n" if line.endswith("\n") else ""
            line = line_marker.sub("", line.rstrip("\n"), count=1) + ending
        if not keep:
            out.append(REMOVED)
            continue
        if (stack or marked) and dormant.match(line):
            line = dormant.sub(r"\1", line, count=1)
        out.append(line)
    assert not stack, f"{path}: {stack[-1][0]}:begin without an end"
    if changed:
        # Where removed lines sat between two blank lines, keep one blank line.
        text = re.sub(r"\n\n(?:\x00\n)+\n", "\n\n", "".join(out))
        path.write_text(text.replace(REMOVED, ""))
PY

if [ "$RENDER_ONLY" = true ]; then
    exit 0
fi

# The stamp: which template commit and options made this project, so template.py can merge later
# template changes into it (TEMPLATE.md, "Updating projects").
if COMMIT="$(git -C "$TEMPLATE" rev-parse --verify HEAD 2>/dev/null)"; then
    MODIFIED=false
    if [ -n "$(git -C "$TEMPLATE" status --porcelain)" ]; then
        MODIFIED=true
        echo "Note: the template has uncommitted changes, so the stamp in .template.json is approximate." >&2
    fi
    python3 - "$DEST/.template.json" "$COMMIT" "$NAME" "$TYPE" "$BENCHMARKS" "$FLY" "$DATABASE" "$MODIFIED" <<'PY'
import json, sys

path, commit, name, kind, benchmarks, fly, database, modified = sys.argv[1:]
stamp = {"commit": commit, "name": name, "type": kind,
         "benchmarks": benchmarks == "true", "fly": fly == "true", "database": database == "true"}
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
else
    echo "  2. Replace the Greetings example: add your first module to MODULES in scripts/modules.py,"
    echo "     remove the Greetings rows and directories, run \`just modules\`."
fi
next "git add -A && git commit -m \"[main] - $NAME from the project template\""
next "On GitHub: add the BUILDBUDDY_API_KEY secret (optional) and set Pages to deploy from gh-pages."
if [ "$FLY" = true ]; then
    next "Fly.io: \`fly launch --no-deploy --copy-config --name $LOWER\` (app names are global; if"
    echo "     $LOWER is taken, change \`app\` in fly.toml), then add a FLY_API_TOKEN secret on GitHub"
    echo "     from \`fly tokens create deploy\`. Every push to main deploys."
fi
if [ "$DATABASE" = true ] && [ "$FLY" = true ]; then
    next "The volume: \`fly volumes create data --size 1 --region den\`."
fi
if [ "$LITESTREAM" = true ]; then
    next "Litestream: create a B2 bucket and application key, then"
    echo "     \`fly secrets set B2_KEY_ID=… B2_APPLICATION_KEY=… B2_BUCKET_NAME=… B2_ENDPOINT=https://s3.<region>.backblazeb2.com\`."
    echo "     Until B2_BUCKET_NAME is set the server runs without replication."
fi
