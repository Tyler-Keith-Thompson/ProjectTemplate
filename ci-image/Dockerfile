# The container CI's Bazel jobs run in: Swift, Bazelisk, and the Bazel that .bazelversion pins,
# already downloaded, with what rules_swift and rules_swift_package_manager call. Built and
# pushed by ci-image/build.sh as ghcr.io/tyler-keith-thompson/swift-bazel:<swift>-<bazel>.
ARG SWIFT_VERSION=6.3
FROM swift:${SWIFT_VERSION}

LABEL org.opencontainers.image.source=https://github.com/Tyler-Keith-Thompson/ProjectTemplate
LABEL org.opencontainers.image.description="Swift and Bazel (through Bazelisk, with the pinned Bazel already downloaded) for the project template's CI"
LABEL org.opencontainers.image.licenses=Apache-2.0

ARG BAZELISK_VERSION=v1.29.0
ARG BAZEL_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 5 -o /usr/local/bin/bazel \
        "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/bazel

# Bazelisk keeps the Bazel it downloads here rather than under $HOME, which GitHub Actions
# replaces in a container job. A project pinning another version still works; Bazelisk
# downloads that one when it runs.
ENV BAZELISK_HOME=/opt/bazelisk
RUN test -n "${BAZEL_VERSION}" \
    && USE_BAZEL_VERSION="${BAZEL_VERSION}" bazel --batch version

# The image has clang but no gcc, which is where rules_cc looks first.
ENV CC=clang
