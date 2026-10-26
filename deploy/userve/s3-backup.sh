#!/bin/sh
set -eu
set -o pipefail
umask 077

# Serialize scheduled and manually triggered runs, releasing the lock on exit.
exec 9>/tmp/titine-backup.lock
flock -n 9 || { echo 'Another Titine backup is running.' >&2; exit 1; }
export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:?}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:?}"
export AWS_DEFAULT_REGION="${S3_REGION:?}"
export AWS_PAGER=''
export PGPASSWORD="${POSTGRES_PASSWORD:?}"
: "${S3_BUCKET:?}" "${POSTGRES_DATABASE:?}" "${POSTGRES_HOST:?}"
prefix="${S3_PREFIX:-backups}/${POSTGRES_DATABASE}/"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
destination="s3://${S3_BUCKET}/${prefix}${stamp}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cd "$work"

echo "Creating Titine database and photo backup: $stamp"
pg_dump --format=custom --no-owner --no-acl \
  -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" \
  -U "${POSTGRES_USER:?}" -d "$POSTGRES_DATABASE" > database.dump
pg_restore --list database.dump >/dev/null
tar -czf storage.tar.gz -C /storage .
gzip -t storage.tar.gz
sha256sum database.dump storage.tar.gz > SHA256SUMS

# Publish the checksum manifest last: only these sets are complete.
for file in database.dump storage.tar.gz SHA256SUMS; do
  aws s3 cp "$file" "$destination/$file" --sse AES256 --only-show-errors
done
echo "Backup complete: $destination"

# Prune only this application's prefix, and only after a complete new backup.
keep_days=${BACKUP_KEEP_DAYS:-30}
case "$keep_days" in ''|*[!0-9]*) echo 'Invalid BACKUP_KEEP_DAYS' >&2; exit 1 ;; esac
cutoff=$(date -u -d "@$(( $(date +%s) - keep_days * 86400 ))" +%Y-%m-%dT%H:%M:%S)
aws s3api list-objects-v2 --bucket "$S3_BUCKET" --prefix "$prefix" \
  --query "Contents[?LastModified<'$cutoff'].Key" --output text > old-keys
tr '\t' '\n' < old-keys | while IFS= read -r key; do
  case "$key" in
    "$prefix"*) aws s3 rm "s3://$S3_BUCKET/$key" --only-show-errors ;;
    ''|None) ;;
    *) echo 'Unexpected key outside backup prefix; refusing deletion.' >&2; exit 1 ;;
  esac
done
echo "Retention applied: $keep_days days."
