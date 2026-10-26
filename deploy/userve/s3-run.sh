#!/bin/sh
set -eu
# go-cron accepts @daily and logs each run's exit status to Docker logs.
exec go-cron "${SCHEDULE:-@daily}" /bin/sh /titine-backup.sh
