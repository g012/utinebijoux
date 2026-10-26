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
- `backups/`: private database dumps and photo archives. Deployment takes a backup before migrations and after startup. A daily backup is scheduled in the user’s crontab at 03:20 server time; `bin/backup.sh` can also run manually. Copy backups off-host and define retention for long-term operation.

Persistent volumes: `titine-postgres-data` (PostgreSQL 18) and `titine-storage` (shared Active Storage disk). Do not delete them during an update. Network `titine` connects only the new database, web and worker; the web container also joins `kamal` for proxy routing. PostgreSQL is not published on a host port.

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
