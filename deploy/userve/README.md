# userve — titine.gros.bid

Deployment uses Docker on `userve` and adds the `titine-web` service to the existing Kamal proxy. The proxy handles HTTPS with Let's Encrypt. Existing applications and their databases are not restarted or reconfigured.

## Deploy

With SSH access to `userve`, commit application changes, then run:

```sh
script/deploy-userve
```

It builds the committed Git revision remotely, migrates the dedicated database, imports missing catalogue records/photos/sizes without resetting existing stock, creates the initial admin if needed, checks the new web container, and switches the proxy target. A Solid Queue worker runs separately. Replaced containers are stopped and retained for rollback.

All files on userve are under `/home/g012/apps/titine/`. Secrets are generated there, mode 600, and never committed or printed. The initial deployment uses application commit `ff234dd`.

- `secrets/production.env`: Rails, database connection, shop configuration, Stripe and SMTP.
- `secrets/postgres.env`: dedicated database credentials.
- `secrets/admin-initial-password`: initial password for `lesbijouxdetitine@gmail.com` at `/session/new` (administration at `/admin`). Retrieve it privately over SSH; changing it later must use the site's password flow once SMTP is configured.
- `current-web`, `current-worker`, `current-revision`: active deployment identifiers.
- `releases/`: archived committed source used by Docker builds.
- `backups/`: private local database dumps and photo archives. Deployment takes a backup before migrations and after startup. A daily local backup is scheduled in the user’s crontab at 03:20 server time; `bin/backup.sh` can also run manually. The S3 accessory below provides off-host backups with 30-day retention. Local archives are retained independently.

Persistent volumes: `titine-postgres-data` (PostgreSQL 18) and `titine-storage` (shared Active Storage disk). Do not delete them during an update. Network `titine` connects only the new database, web and worker; the web container also joins `kamal` for proxy routing. PostgreSQL is not published on a host port.

## S3 backup accessory

`config/deploy.backups.yml` manages only `titine-s3_backup` using Kamal 2, independently of application releases. It uses a pinned PostgreSQL 18 backup image (a PostgreSQL 17 client cannot dump this database), joins the private `titine` network, and mounts the photo volume read-only. It has no published ports or Docker socket.

The container runs daily at midnight UTC (`@daily`). Each set contains a custom-format PostgreSQL dump, an archive of the complete Active Storage directory, and a SHA256 manifest uploaded last to mark completion:

```text
s3://titine/backups/titine_production/YYYYMMDDTHHMMSSZ/
  database.dump
  storage.tar.gz
  SHA256SUMS
```

Uploads request S3 encryption (`AES256`). After a successful upload, objects older than 30 days are removed only under `backups/titine_production/`. Configure `BACKUP_KEEP_DAYS` in the accessory to change retention. S3 versioning/lifecycle settings, if enabled, govern noncurrent object versions separately.

`.kamal/backups-secrets` obtains `s3.access_key_id` and `s3.secret_access_key` from local Rails credentials using `mise exec`; it reads the existing PostgreSQL password over SSH. No raw secrets belong in Git. Kamal stores the accessory env file privately on userve. The IAM identity needs `s3:ListBucket` on `arn:aws:s3:::titine` (restricted to this prefix if desired), and `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on `arn:aws:s3:::titine/backups/titine_production/*`.

Run from this checkout with the local Rails master key and Kamal 2 installed:

```sh
kamal accessory boot s3_backup -c config/deploy.backups.yml
# Apply configuration changes or rotated credentials:
kamal accessory reboot s3_backup -c config/deploy.backups.yml
kamal accessory logs s3_backup -c config/deploy.backups.yml
# Trigger a backup immediately:
ssh userve 'docker exec titine-s3_backup /bin/sh /titine-backup.sh'
```

To restore, download all three files from a completed set into a private directory and run `sha256sum -c SHA256SUMS`. Restore `database.dump` with PostgreSQL 18 `pg_restore --exit-on-error --no-owner --no-acl` into an empty database, and extract `storage.tar.gz` into an empty storage volume. Verify the restored catalogue and photos before switching the application. Stop writes and workers for an actual production restore; never restore over the live database as a test. The database dump is transactionally consistent; the photo archive is captured immediately afterwards, so a concurrent photo deletion can require using an older backup set.

## Enable payments and email

The catalogue works without Stripe/SMTP credentials; Checkout reports unavailable until Stripe is configured. Add these to `secrets/production.env` on userve:

```text
STRIPE_SECRET_KEY=...
STRIPE_WEBHOOK_SECRET=...
SMTP_ADDRESS=...
SMTP_PORT=587
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

Keep the same Stripe account for all orders. Add the signed endpoint `https://titine.gros.bid/stripe/webhook` with the four Checkout events documented in the main README. Configure a mail provider authorized to send for `SHOP_EMAIL`; then recreate web/worker containers with the updated environment, reusing the current image:

```sh
ssh userve '/home/g012/apps/titine/bin/release.sh "$(cat /home/g012/apps/titine/current-revision)"'
```

A full `script/deploy-userve` also refreshes the environment. Editing an env file does not change existing containers.

Never regenerate `SECRET_KEY_BASE` or database passwords during routine deployments. The bootstrap script preserves existing secret files.

## Inspect and rollback

```sh
ssh userve 'docker ps --filter label=service=titine'
ssh userve 'docker logs --tail 100 "$(cat /home/g012/apps/titine/current-web)"'
ssh userve 'docker logs --tail 100 "$(cat /home/g012/apps/titine/current-worker)"'
ssh userve 'docker exec kamal-proxy kamal-proxy list'
```

For rollback, restart a retained previous web container and switch only `titine-web` to it with `kamal-proxy deploy`, retaining `--host titine.gros.bid --tls --health-check-host titine.gros.bid`. Stop the newer worker and restart its predecessor. Schema migrations are forward-only operationally; check compatibility before rolling application code back across schema changes.
