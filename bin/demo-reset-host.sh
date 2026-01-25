#!/bin/bash
set -euo pipefail

# Demo reset script for the HOST machine (outside container)
# Copy this to /opt/campfire/demo-reset.sh on the demo server
#
# Cron: 0 * * * * /opt/campfire/demo-reset.sh >> /var/log/demo-reset.log 2>&1

cd /opt/campfire

echo "$(date): Starting demo reset..."

# Stop the web container
echo "$(date): Stopping web container..."
docker compose stop web

# Copy snapshot over production database
echo "$(date): Restoring database from snapshot..."
docker compose run --rm --entrypoint /bin/sh web -c "
  cp /rails/storage/db/demo_snapshot.sqlite3 /rails/storage/db/production.sqlite3
  rm -f /rails/storage/db/production.sqlite3-wal /rails/storage/db/production.sqlite3-shm
"

# Start the web container
echo "$(date): Starting web container..."
docker compose start web

echo "$(date): Demo reset complete!"
