#!/usr/bin/env bash
# Build the CI image for every Swift version the template's workflows use, for arm64 (the
# runners) and amd64, tagged ghcr.io/tyler-keith-thompson/swift-bazel:<swift>-<bazel>.
#
#   ci-image/build.sh           build the images for this machine's architecture only
#   ci-image/build.sh --push    build both architectures and push them (needs gh's
#                               write:packages scope: gh auth refresh -s write:packages)
#
# Run it after changing .bazelversion or a workflow's Swift version, then point the workflows
# at the new tag.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bazel_version="$(cat "$here/../.bazelversion")"
image=ghcr.io/tyler-keith-thompson/swift-bazel
# swift:6.3 for CI.yml and docc.yml; swift:6.3.3 for the embedded type, which pins the patch.
swift_versions=(6.3 6.3.3)

push=false
[ "${1:-}" = "--push" ] && push=true

if [ "$push" = true ]; then
    gh auth token | docker login ghcr.io -u "$(gh api user --jq .login)" --password-stdin
fi
for swift in "${swift_versions[@]}"; do
    tag="$image:$swift-$bazel_version"
    if [ "$push" = true ]; then
        docker buildx build --platform linux/arm64,linux/amd64 --push \
            --build-arg SWIFT_VERSION="$swift" --build-arg BAZEL_VERSION="$bazel_version" -t "$tag" "$here"
    else
        docker buildx build --load \
            --build-arg SWIFT_VERSION="$swift" --build-arg BAZEL_VERSION="$bazel_version" -t "$tag" "$here"
    fi
    echo "$tag"
done
