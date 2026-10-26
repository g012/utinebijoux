#!/usr/bin/env bash
set -euo pipefail
umask 077

TITINE_ROOT=/home/g012/apps/titine
mkdir -p "$TITINE_ROOT/secrets" "$TITINE_ROOT/releases" "$TITINE_ROOT/bin" "$TITINE_ROOT/backups"
chmod 700 "$TITINE_ROOT" "$TITINE_ROOT/secrets" "$TITINE_ROOT/backups"

python3 - <<'PY'
from pathlib import Path
import os
import secrets

root = Path('/home/g012/apps/titine/secrets')
database = root / 'postgres.env'
application = root / 'production.env'
if database.exists() != application.exists():
    raise SystemExit('Incomplete existing configuration; refusing to replace database credentials.')

def write_private(path, values):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(''.join(f'{key}={value}\n' for key, value in values.items()))

if not database.exists():
    password = secrets.token_urlsafe(36)
    write_private(database, {
        'POSTGRES_USER': 'titine',
        'POSTGRES_DB': 'titine_production',
        'POSTGRES_PASSWORD': password,
    })
    write_private(application, {
        'RAILS_ENV': 'production',
        'APP_URL': 'https://titine.gros.bid',
        'DATABASE_URL': f'postgresql://titine:{password}@titine-postgres:5432/titine_production',
        'SECRET_KEY_BASE': secrets.token_hex(64),
        'SHOP_NAME': 'les bijoux de titine',
        'SHOP_EMAIL': 'lesbijouxdetitine@gmail.com',
        'ADMIN_EMAIL': 'lesbijouxdetitine@gmail.com',
        'FRANCE_SHIPPING_CENTS': '200',
        'RAILS_MAX_THREADS': '5',
        'JOB_CONCURRENCY': '1',
        'STRIPE_SECRET_KEY': '',
        'STRIPE_WEBHOOK_SECRET': '',
        'SMTP_ADDRESS': 'localhost',
        'SMTP_PORT': '587',
        'SMTP_USERNAME': '',
        'SMTP_PASSWORD': '',
    })
initial = root / 'admin-initial-password'
if not initial.exists():
    fd = os.open(initial, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(secrets.token_urlsafe(24) + '\n')
print('Private production configuration ready; no credentials printed.')
PY

if ! docker network inspect titine >/dev/null 2>&1; then
  docker network create --label service=titine titine >/dev/null
fi
docker volume create --label service=titine titine-postgres-data >/dev/null
docker volume create --label service=titine titine-storage >/dev/null
if ! docker inspect titine-postgres >/dev/null 2>&1; then
  docker run -d --name titine-postgres --restart unless-stopped \
    --label service=titine --label role=database --network titine \
    --memory 768m --shm-size 128m \
    --env-file "$TITINE_ROOT/secrets/postgres.env" \
    --mount type=volume,source=titine-postgres-data,target=/var/lib/postgresql \
    --health-cmd='pg_isready -U titine -d titine_production' \
    --health-interval=5s --health-timeout=3s --health-retries=12 \
    pgvector/pgvector:pg18 >/dev/null
else
  docker start titine-postgres >/dev/null
fi
for attempt in $(seq 1 60); do
  if docker exec titine-postgres pg_isready -U titine -d titine_production >/dev/null 2>&1; then
    printf 'Titine PostgreSQL is ready.\n'
    exit 0
  fi
  sleep 1
done
printf 'PostgreSQL did not become ready.\n' >&2
exit 1
