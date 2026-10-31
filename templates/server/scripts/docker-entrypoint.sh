#!/bin/sh
# The image's entry point. With B2_BUCKET_NAME set (a Fly secret), restores the database from its
# replica when the volume holds none, then runs the server under Litestream, which replicates
# every write until the server exits. Without it (`just docker`), runs the server alone.
set -eu

SERVE="/app/ProjectNameServer serve --env production --hostname 0.0.0.0 --port 8080"

if [ -n "${DATABASE_PATH:-}" ]; then
    mkdir -p "$(dirname "$DATABASE_PATH")"
fi

if [ -z "${B2_BUCKET_NAME:-}" ]; then
    echo "B2_BUCKET_NAME is unset: serving without replication." >&2
    exec $SERVE
fi

litestream restore -config /etc/litestream.yml -if-db-not-exists -if-replica-exists "$DATABASE_PATH"
exec litestream replicate -config /etc/litestream.yml -exec "$SERVE"
