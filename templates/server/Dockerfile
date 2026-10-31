# syntax=docker/dockerfile:1
# The production image: the server built by SwiftPM in release, on a plain Ubuntu runtime.
# `just docker` builds and runs it locally; Fly.io builds it from fly.toml.

FROM swift:6.3-noble AS build
WORKDIR /build

# Dependencies first, so a source change reuses them. swift/Package.resolved pins the same
# packages for Bazel, so the image builds the versions the tests ran against.
COPY Package.swift ./
COPY swift/Package.resolved ./Package.resolved
RUN swift package resolve --force-resolved-versions

# SwiftPM checks that every target's directory exists, tests included.
COPY Sources ./Sources
COPY Tests ./Tests
RUN --mount=type=cache,target=/build/.build \
    swift build -c release --product ProjectNameServer --static-swift-stdlib \
 && mkdir -p /staging \
 && cp "$(swift build -c release --show-bin-path)/ProjectNameServer" /staging/ \
 && cp /usr/libexec/swift/linux/swift-backtrace-static /staging/
# litestream:begin

# Litestream replicates the SQLite database to object storage (litestream.yml).
ARG LITESTREAM_VERSION=0.5.17
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && arch="$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo x86_64)" \
 && curl -fsSL "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-${arch}.tar.gz" \
    | tar -xz -C /staging litestream
# litestream:end

FROM ubuntu:noble
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /staging/ProjectNameServer /staging/swift-backtrace-static /app/
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=/app/swift-backtrace-static
EXPOSE 8080
# litestream:begin
COPY --from=build /staging/litestream /usr/local/bin/litestream
COPY litestream.yml /etc/litestream.yml
COPY scripts/docker-entrypoint.sh /app/docker-entrypoint.sh
ENTRYPOINT ["/app/docker-entrypoint.sh"]
# litestream:end
# !litestream:begin
ENTRYPOINT ["/app/ProjectNameServer"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
# !litestream:end
