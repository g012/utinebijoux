# A small handmade jewelry atelier

French boutique built with **Ruby 4.0.7, Rails 8.1.4, PostgreSQL**, Hotwire (Turbo + Stimulus), Tailwind CSS, Active Storage, the official Stripe Ruby gem, and Active Job / Solid Queue. `SHOP_NAME` defaults to **les bijoux de titine**.

The application includes a responsive storefront, categories and search, product pages, anonymous carts, hosted payment, order confirmation, transactional emails, and an authenticated admin area. No customer accounts or public admin registration.

## Local setup

Requirements: Ruby 4.0.7, Bundler, PostgreSQL 14+, libpq development headers, and libvips. Node and Redis are not required. For example, on Debian/Ubuntu install `libpq-dev libvips` before bundling. Install Ruby using your preferred version manager (`mise install ruby@4.0.7`, for example).

```sh
bundle install
cp .env.example .env
# Edit .env, then export it for standalone Rails commands:
set -a
. ./.env
set +a
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

Open http://localhost:3000. `bin/dev` starts Puma, the Tailwind watcher, and the Solid Queue worker. Foreman reads `.env` automatically. For standalone commands, export the environment as above; Rails itself does not automatically load `.env`. `bin/setup --skip-server` also installs dependencies and prepares the database.

Default databases are `bijoux_development` and `bijoux_test`. The local PostgreSQL role defaults to the OS user; it must be able to create databases. Use `DATABASE_URL` when needed. Never point the test suite at production. CI provisions its own PostgreSQL service.

The development seeds import the creator’s catalogue from `db/catalogue.yml` and the original photos in `db/catalogue/photos/`. There are 42 creations: 25 bead bracelets, 5 thread bracelets, 5 rings, and 7 keyrings. Bracelets and rings have two views; each keyring has one photo (77 originals in total). Photos are attached through Active Storage, and their source files remain in the repository for repeatable setup.

The four categories are `Bracelets en perles`, `Bracelets en fil`, `Bagues`, and `Porte-clés`. Optional `collection` is independent of category; `Les fruits` can span categories. White-background creations remain outside a collection. The received `tmp/nocollection` folder contains 36 creations (65 photos), and `tmp/lesfruits` contains six fruit bracelets (12 photos). All six fruit bracelets belong to `Bracelets en perles` and the `Les fruits` collection. They each have one 15 cm and one 18 cm example; Cerises and Cerises sakura also have one 20 cm example (14 bracelets total). The public product form requires a length, and the cart, immutable order snapshot, Stripe line item, confirmation emails, and admin order all preserve it. Their two-view pairs are explicitly mapped in the manifest, including nonconsecutive filenames (`image00008`/`image00011`, `image00014`/`image00016`, `image00015`/`image00017`).

Run `bin/rails catalogue:import` to import again without resetting prices, stock, names, publication state, or photo order. Stable catalogue references prevent duplicates; only missing photos and new sizes are added. Re-importing never resets existing size stock, including sold or reserved sizes. A product with a pending unsized order cannot be converted to sized inventory until that reservation finishes. Existing placeholder products are archived, preserving their records. Initial names are factual, editable descriptions. The creator confirmed **€3 per ring and €6 for every other creation**: the manifest sets ring `price_cents` to 300 and other products to 600, with stock 1 per unsized item or per length. The imported catalogue is published. All creations outside `Les fruits` display “Taille unique” in the listing, product page and cart; the fruit collection retains its selectable lengths. A draft may have a blank price; publishing requires a strictly positive price at both model and database level. Future unpriced creations can still be prepared as drafts and published through `/admin/products`. Demo images retained in `public/images` are no longer used on public pages.

## Admin

All `User` records are administrators; there is no signup route. Create the first one with a unique password of at least 12 characters. Avoid putting a password in shell history:

```sh
export ADMIN_EMAIL=you@example.com
read -rs -p 'Admin password: ' ADMIN_PASSWORD
export ADMIN_PASSWORD
bin/rails admin:create
unset ADMIN_PASSWORD
```

Sign in at `/session/new`, then visit `/admin`. Existing accounts use the password reset flow; the create task will not overwrite their password. Admins can publish products with the default stock of one, manage multiple photos, reorder the cover photo, remove photos, adjust available stock, and archive products. Prices default to €6 and are entered in cents (`600` = €6). Open advanced settings to mark a repeatable product, change stock, or hide a sold product automatically. Stock changes, including size inventories, are blocked while that product has a pending payment, to protect existing reservations. In advanced settings, each length has its own stock; set it to zero to withdraw that size, or add another length with its initial stock. Existing lengths keep their identity. Orders and shipping details are visible in admin. Archiving preserves previous order records.

## Stripe development and webhook testing

Set `STRIPE_SECRET_KEY=sk_test_...`. A publishable key is unnecessary because the app redirects to Stripe's hosted Checkout. No card details pass through the application. Only card payment methods are enabled, including Apple Pay / Google Pay when supported by Checkout and the customer's device/account. Collect billing details and a shipping address in France.

Install the [official Stripe CLI](https://docs.stripe.com/stripe-cli), authenticate to your test account, and forward the four supported events:

```sh
stripe login
stripe listen --events checkout.session.completed,checkout.session.expired,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed --forward-to localhost:3000/stripe/webhook
```

Copy the printed `whsec_...` into `STRIPE_WEBHOOK_SECRET` in `.env`, then restart `bin/dev`. The forwarding secret differs from a Dashboard endpoint's secret. `APP_URL` must match the address used in your browser; it sets trusted Checkout return URLs and email links.

1. Browse `/boutique`, open a product, add to cart, and start payment.
2. Use Stripe's test card `4242 4242 4242 4242`, any future expiry, and any CVC, with a French test address.
3. Check the forwarded signed `checkout.session.completed` returns HTTP 200.
4. The success page should change from pending to paid. Refreshing never creates a sale. Inspect `/admin/orders` and verify available stock stays zero.
5. Check the worker log for customer and admin emails. Development delivery is logged rather than sent via SMTP.
6. Replay the same event from Stripe: stock and confirmation enqueueing must not change a second time. A generic `stripe trigger checkout.session.completed` is not sufficient: its generated session is unrelated to an application order.
7. To test abandonment without waiting 35 minutes, expire the actual session using `stripe checkout sessions expire cs_test_...`, or use **Annuler cette réservation** in the cart. Stock returns after confirmed expiration.

For declines, try `4000 0000 0000 0002`; a recoverable card decline does **not** release stock while Checkout is still open. Inspect Stripe test data for reconciliation using the stored session ID, Payment Intent ID, order reference, and `metadata.order_token`.

## Inventory and failures

`Product.stock_quantity` is **available** stock for products without sizes. For a sized bracelet, `ProductSize.stock_quantity` is authoritative for each length; `Product.available_stock` computes the total. The generic product stock is ignored for purchasing, availability filters, and sold-out visibility when sizes exist. Adding to a cart never reserves it. A signed, HttpOnly, SameSite=Lax cookie identifies a server-side `Cart` (30 days); cookies contain neither authoritative prices nor quantities.

`Checkout.reserve` locks the cart, then all requested product rows and size rows in ascending ID order in one PostgreSQL transaction. It requires a size belonging to that product and reserves only that length. It checks visibility, stock and quantities, builds a pending order with immutable item names/prices/quantities, subtracts available stock, and moves cart items into that order. Any unavailable line rolls back the whole basket. A partial unique index allows at most one pending order per cart. Separate real PostgreSQL connections test simultaneous purchases of one unique item.

After that commit, Checkout creation holds the order lock and uses a stable Stripe idempotency key. The entire original Stripe request is persisted with the order, so retries use identical amounts, shipping and URLs. The request sets `expires_at` to 35 minutes after reservation (within [Stripe's supported 30-minute to 24-hour range](https://docs.stripe.com/api/checkout/sessions/create#checkout_session_create-expires_at)); the returned Stripe expiration is copied locally.

- Successful signed events mark the order paid under its row lock; they **do not decrement stock again**. Session ID, currency, total, and order reference are checked. Snapshots survive product edits. Duplicate Stripe event IDs have a unique database constraint and are recorded in the same transaction as the state change.
- Expired sessions and definitive asynchronous failures release reserved quantities once under that same order lock and return the selection to the cart without reserving it. Late expiration events cannot undo paid orders. Ordinary `payment_intent.payment_failed` declines are not terminal Checkout failures and do not release inventory.
- Definitive creation validation errors cancel the local order and release it. Timeouts, authentication problems, and API outages retain the reservation because a remotely created session could still be payable. Retrying before expiry uses the original idempotency key.
- If a response was lost before saving the session ID, a signed webhook can bind it using the order token. After expiry, cleanup also scans Stripe sessions created since reservation, following pagination, to recover the matching session. It releases a sessionless reservation only after a successful remote lookup confirms none exists. Never rotate to a different Stripe account while unresolved orders exist.
- `CleanupReservationsJob` runs every five minutes in production. For known sessions it checks Stripe, expires open sessions, reconciles already paid ones, and retains completed/unpaid sessions pending a final event. Stripe outages retain inventory and are reported through `Rails.error`. Monitor this and pending orders; rerun cleanup after an outage.
- The success page is read-only; opening, refreshing, or guessing sequential IDs cannot mark an order paid. Capability URLs use random 32-character tokens and send no-store/no-referrer/noindex headers. Treat those links as private.

Emails run asynchronously. A paid-order callback enqueues `SendOrderConfirmationJob`; cleanup also catches missed enqueues. Both mail jobs and the marker are committed in the **same primary PostgreSQL database** through Solid Queue, so duplicate payment deliveries do not enqueue a second pair. SMTP delivery is inherently at least once if a worker loses its connection after SMTP accepts a message.

To run cleanup manually:

```sh
bin/rails runner 'CleanupReservationsJob.perform_now'
```

Shipping is France-only, at a flat **€2 per order regardless of item count**, centralized in `Shop.shipping_cents` (`FRANCE_SHIPPING_CENTS`, default 200). Subtotal, shipping, total, and currency are snapshots on every order. Setting shipping to `0` enables free shipping without a schema change. Refunds are handled in Stripe for this MVP; do not restock automatically. Verify the refund and physical return before a stock adjustment. The optional `refunded` state is available for manually reconciled orders; automatic refund events and a fulfillment/carrier integration are outside this MVP.

## Storage, jobs and email

Active Storage stores multiple JPEG/PNG/WebP photos (max 10 × 10 MB per product). Local files live in `storage/`; keep a **persistent shared disk** with backups in production. Every web/worker instance must access the same storage path. `config/storage.yml` is the place to configure an object store later. libvips supports Active Storage analysis/variants; original uploads are displayed initially.

Solid Queue tables live in the **primary database**, installed through regular migrations. Run `bin/jobs` as a supervised process in production; its supervisor runs the recurring cleanup scheduler. Do not configure a separate queue database without redesigning the transactional mail enqueue. Inspect failed jobs and application error logs.

Production mail uses `SMTP_ADDRESS`, `SMTP_PORT` (587), `SMTP_USERNAME`, `SMTP_PASSWORD`, and `SHOP_EMAIL` as sender. Set `ADMIN_EMAIL` for sale notifications. Configure SPF/DKIM/DMARC with the mail provider. Password-reset mail also runs asynchronously.

## Tests and checks

```sh
bin/rails db:test:prepare
bin/rails test
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit check --update
bin/importmap audit
bin/rails zeitwerk:check
```

Tests use Stripe doubles and locally signed webhook payloads, never live Stripe calls. Coverage includes one-copy defaults, unavailable quantities, cart isolation, forged prices, real concurrent PostgreSQL reservations, duplicate/late webhooks, signature verification, network uncertainty, crash recovery, expiration, snapshots, email enqueueing, authentication, and admin stock protection.

## Production checklist

- Supply `DATABASE_URL`, `SECRET_KEY_BASE` (`bin/rails secret`), HTTPS `APP_URL`, live `STRIPE_SECRET_KEY`, the production `STRIPE_WEBHOOK_SECRET`, SMTP settings, `SHOP_NAME`, `SHOP_EMAIL`, and `ADMIN_EMAIL`. Never commit `.env`, master keys, or credentials. The generated development `config/master.key` is ignored; runtime can use `SECRET_KEY_BASE` directly.
- Complete and review the French legal placeholders (seller identity, tax/VAT presentation, withdrawal/returns, delivery timelines, legal guarantees, mediation and privacy/retention), real contact information, product materials/dimensions and all product/hero photos **before opening sales**.
- Configure the public HTTPS Stripe endpoint `/stripe/webhook` for the four events listed above, using the Checkout API version matching the installed Stripe gem. Confirm the shipping fields from a real test payment. Apple Pay / Google Pay availability is managed by Stripe.
- Create the admin account, prepare the database (`RAILS_ENV=production bin/rails db:prepare`), and precompile assets. Run the web process and `bin/jobs` with the same environment, database, and shared storage. Terminate HTTPS at a trusted proxy; Rails forces SSL and restricts hosts to `APP_URL`.
- Back up PostgreSQL and `storage/`; monitor webhook failures, old pending orders, Solid Queue failures, disk usage and email delivery. Confirm a real Stripe test checkout and webhook before switching to live keys.
- Update the sitemap comment in `public/robots.txt` to your public `/sitemap.xml` URL. Product pages include stable slugs, canonical titles/descriptions, Open Graph metadata, image alt text and JSON-LD offers.

A production Dockerfile is included; pass environment variables at runtime and mount `/rails/storage`. Run a second container from the same image with `bin/jobs`. The Docker build and a real hosted Stripe payment need deployment/account access and are not part of the offline automated suite.

Key entry points: `app/services/checkout.rb`, `stripe_checkout_event.rb`, `reconcile_checkout.rb`; `app/models/{product,order,order_item}.rb`; `app/controllers/admin/`; `app/jobs/`; `config/initializers/shop.rb`; `config/recurring.yml`; `app/assets/tailwind/application.css`; and `test/`.
