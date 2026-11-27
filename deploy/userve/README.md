# userve — titine.gros.bid

Deployment uses Kamal 2 (`config/deploy.yml`) on `userve`, sharing the existing `kamal-proxy` with the other Kamal apps on that server. The proxy handles HTTPS with Let's Encrypt. Other applications and their databases are never touched.

## Deploy

With SSH access to `userve` (as `g012`) and Docker running locally, commit application changes, then run:

```sh
bin/kamal deploy
```

Kamal builds the committed Git revision locally, pushes it to a local registry (`localhost:5555`) that `userve` pulls through an SSH tunnel, then:

1. `pre-deploy` hook (`.kamal/hooks/pre-deploy`): installs `deploy/userve/backup.sh` on userve and backs up the database and photos.
2. Boots the new web container; its entrypoint runs `db:migrate catalogue:import` (imports missing catalogue records/photos/sizes without resetting existing stock; demo seeds never run).
3. `kamal-proxy` switches `titine-web` to the new container once `/up` is healthy, with no downtime.
4. Boots the Solid Queue worker (`job` role) after the web is healthy, and stops the previous containers (the last five are retained for rollback).

Useful commands:

```sh
bin/kamal logs                 # follow web logs (-r job for the worker)
bin/kamal console              # Rails console in the running web container
bin/kamal dbc                  # psql via Rails dbconsole
bin/kamal backup               # immediate local backup on userve
bin/kamal app details          # running containers
bin/kamal rollback <version>   # previous Git SHA, see `bin/kamal app containers`
```

Schema migrations are forward-only operationally; check compatibility before rolling application code back across schema changes.

## Secrets and configuration

Non-secret configuration is in `config/deploy.yml` (`env.clear`). Secrets are resolved at deploy time by `.kamal/secrets` through `script/kamal-secret` and are never committed or printed:

- `/home/g012/apps/titine/secrets/production.env` on userve (mode 600): `DATABASE_URL`, `SECRET_KEY_BASE`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SMTP_USERNAME`, `SMTP_PASSWORD`. Only these keys are read.
- `/home/g012/apps/titine/secrets/postgres.env`: `POSTGRES_PASSWORD`.
- Local Rails credentials (`config/master.key`): `s3.access_key_id`, `s3.secret_access_key`.

Never regenerate `SECRET_KEY_BASE` or database passwords. Keep an off-host copy of the `secrets/` directory: it is not part of the backups.

The initial administrator (`lesbijouxdetitine@gmail.com`, password in `secrets/admin-initial-password`) already exists. On a new database, create it with `bin/kamal app exec -i --reuse 'ADMIN_PASSWORD=... bin/rails admin:create'`.

## Enable payments and email

The catalogue works without Stripe/SMTP credentials; Checkout reports unavailable until Stripe is configured. Fill these in `secrets/production.env` on userve, and set `SMTP_ADDRESS`/`SMTP_PORT` in `config/deploy.yml`:

```text
STRIPE_SECRET_KEY=...
STRIPE_WEBHOOK_SECRET=...
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

Keep the same Stripe account for all orders. Add the signed endpoint `https://titine.gros.bid/stripe/webhook` with the four Checkout events documented in the main README. Configure a mail provider authorized to send for `SHOP_EMAIL`, then run `bin/kamal deploy` (or `bin/kamal env push && bin/kamal app boot` to reuse the current image). Editing the env file does not change running containers.

## Containers, volumes and network

- `titine-web-<sha>`, `titine-job-<sha>`: application roles, on the `kamal` network (proxy) and the private `titine` network.
- `titine-postgres`: Kamal accessory `postgres` (PostgreSQL 18 with pgvector), only on `titine`, no published port.
- `titine-s3_backup`: Kamal accessory `s3_backup`, only on `titine`.

Persistent volumes: `titine-postgres-data` and `titine-storage` (Active Storage photos). Do not delete them. Accessories are not restarted by `bin/kamal deploy`; use `bin/kamal accessory reboot <name>` after changing their configuration (`postgres` restarts cause a short outage).

## Backups

- Local: `backups/` on userve holds database dumps and photo archives, made before each deploy and daily at 03:20 server time (user crontab running `bin/backup.sh`).
- Off-host: the `s3_backup` accessory runs daily at midnight UTC.

Each S3 set contains a custom-format PostgreSQL dump, an archive of the complete Active Storage directory and a SHA256 manifest uploaded last to mark completion:

```text
s3://titine/backups/titine_production/YYYYMMDDTHHMMSSZ/
  database.dump
  storage.tar.gz
  SHA256SUMS
```

Uploads request S3 encryption (`AES256`). After a successful upload, objects older than 30 days are removed only under `backups/titine_production/` (`BACKUP_KEEP_DAYS`). The IAM identity needs `s3:ListBucket` on `arn:aws:s3:::titine` and `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on `arn:aws:s3:::titine/backups/titine_production/*`.

```sh
bin/kamal accessory reboot s3_backup     # apply configuration changes or rotated credentials
bin/kamal accessory logs s3_backup
ssh userve 'docker exec titine-s3_backup /bin/sh /titine-backup.sh'   # backup now
```

To restore, download all three files from a completed set into a private directory and run `sha256sum -c SHA256SUMS`. Restore `database.dump` with PostgreSQL 18 `pg_restore --exit-on-error --no-owner --no-acl` into an empty database, and extract `storage.tar.gz` into an empty storage volume. Verify the restored catalogue and photos before switching the application. Stop writes and workers for an actual production restore; never restore over the live database as a test. The photo archive is captured immediately after the dump, so a concurrent photo deletion can require using an older backup set.
