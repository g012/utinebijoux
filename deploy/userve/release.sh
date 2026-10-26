#!/usr/bin/env bash
set -euo pipefail
umask 077

REVISION=${1:?Pass the Git revision used for the image}
[[ "$REVISION" =~ ^[0-9a-f]{7,40}$ ]] || { printf 'Invalid revision.\n' >&2; exit 1; }
TITINE_ROOT=/home/g012/apps/titine
IMAGE="titine:$REVISION"
STAMP=$(date -u +%Y%m%d%H%M%S)
WEB="titine-web-$REVISION-$STAMP"
WORKER="titine-jobs-$REVISION-$STAMP"
COMMON=(--label service=titine --network titine --env-file "$TITINE_ROOT/secrets/production.env"
  --mount type=volume,source=titine-storage,target=/rails/storage)

if [[ -x "$TITINE_ROOT/bin/backup.sh" && -f "$TITINE_ROOT/current-revision" ]]; then
  "$TITINE_ROOT/bin/backup.sh"
fi

# Production imports are explicit; development demo seeds are never executed.
docker run --rm "${COMMON[@]}" "$IMAGE" ./bin/rails db:migrate catalogue:import

docker run --rm "${COMMON[@]}" \
  --mount "type=bind,source=$TITINE_ROOT/secrets/admin-initial-password,target=/run/secrets/titine-admin-password,readonly" \
  "$IMAGE" ./bin/rails runner '
    email = Shop.admin_email.strip.downcase
    user = User.find_or_initialize_by(email_address: email)
    if user.new_record?
      password = File.read("/run/secrets/titine-admin-password").strip
      user.update!(password: password, password_confirmation: password)
    end
    puts "Administrator ready (password not displayed)."
  '

docker run -d --name "$WEB" --restart unless-stopped --memory 1g \
  --label role=web --label "revision=$REVISION" "${COMMON[@]}" "$IMAGE" >/dev/null
docker network connect kamal "$WEB"

healthy=false
for attempt in $(seq 1 60); do
  if docker exec "$WEB" curl --fail --silent --header 'Host: titine.gros.bid' http://127.0.0.1:3000/up >/dev/null 2>&1; then
    healthy=true
    break
  fi
  if [[ "$(docker inspect --format '{{.State.Running}}' "$WEB")" != true ]]; then
    break
  fi
  sleep 1
done
if [[ "$healthy" != true ]]; then
  docker logs --tail 60 "$WEB"
  printf 'New web container did not become healthy; proxy unchanged.\n' >&2
  exit 1
fi

docker exec kamal-proxy kamal-proxy deploy titine-web \
  --host titine.gros.bid --target "$WEB:3000" --tls \
  --health-check-host titine.gros.bid --health-check-path /up \
  --deploy-timeout 120s --drain-timeout 30s

docker run -d --name "$WORKER" --restart unless-stopped --memory 768m \
  --label role=jobs --label "revision=$REVISION" "${COMMON[@]}" "$IMAGE" ./bin/jobs >/dev/null

worker_healthy=false
for attempt in $(seq 1 20); do
  if docker exec "$WORKER" ./bin/rails runner 'require "socket"; abort unless SolidQueue::Process.exists?(hostname: Socket.gethostname, kind: "Worker")' >/dev/null 2>&1; then
    worker_healthy=true
    break
  fi
  sleep 1
done
if [[ "$worker_healthy" != true ]]; then
  docker logs --tail 60 "$WORKER"
  printf 'Worker did not become ready; previous containers retained.\n' >&2
  exit 1
fi

# Keep the preceding containers stopped for rollback; retain every data volume.
for role in web jobs; do
  while IFS= read -r container; do
    [[ -z "$container" || "$container" == "$WEB" || "$container" == "$WORKER" ]] && continue
    docker stop --time 30 "$container" >/dev/null
  done < <(docker ps --filter label=service=titine --filter "label=role=$role" --format '{{.Names}}')
done
printf '%s\n' "$WEB" > "$TITINE_ROOT/current-web"
printf '%s\n' "$WORKER" > "$TITINE_ROOT/current-worker"
printf '%s\n' "$REVISION" > "$TITINE_ROOT/current-revision"
printf 'Deployed %s to https://titine.gros.bid\nWeb: %s\nWorker: %s\n' "$REVISION" "$WEB" "$WORKER"
