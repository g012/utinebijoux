#!/usr/bin/env bash
set -euo pipefail
umask 077
TITINE_ROOT=/home/g012/apps/titine
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REVISION=$(cat "$TITINE_ROOT/current-revision")
[[ "$REVISION" =~ ^[0-9a-f]{7,40}$ ]] || exit 1
mkdir -p "$TITINE_ROOT/backups"
# Use PostgreSQL 18's own pg_dump, not the application image's client version.
docker exec titine-postgres pg_dump -U titine -d titine_production --no-owner --no-acl \
  | gzip > "$TITINE_ROOT/backups/$STAMP.sql.gz.partial"
mv "$TITINE_ROOT/backups/$STAMP.sql.gz.partial" "$TITINE_ROOT/backups/$STAMP.sql.gz"
docker run --rm --network none --entrypoint tar \
  --mount type=volume,source=titine-storage,target=/storage,readonly \
  "titine:$REVISION" -czf - -C /storage . > "$TITINE_ROOT/backups/$STAMP.storage.tar.gz.partial"
mv "$TITINE_ROOT/backups/$STAMP.storage.tar.gz.partial" "$TITINE_ROOT/backups/$STAMP.storage.tar.gz"
printf 'Database and photos backed up: %s\n' "$STAMP"
