#!/bin/bash
set -euo pipefail

# Demo reset script for the HOST machine (outside container)
# Copy this to /opt/campfire/demo-reset.sh on the demo server
#
# Cron: 0 * * * * /opt/campfire/demo-reset.sh >> /var/log/demo-reset.log 2>&1
#
# Note: Demo servers don't have litestream (backups disabled), so we only
# need to stop/start the web container.

cd /opt/campfire

echo "$(date): Starting demo reset..."

# Stop the web container
echo "$(date): Stopping web container..."
docker compose stop web

# Copy snapshot over production database and remove WAL files
echo "$(date): Restoring database from snapshot..."
docker run --rm -v campfire_campfire_data:/rails/storage alpine sh -c "
  rm -f /rails/storage/db/production.sqlite3-wal /rails/storage/db/production.sqlite3-shm
  cp /rails/storage/db/demo_snapshot.sqlite3 /rails/storage/db/production.sqlite3
"

# Start the web container
echo "$(date): Starting web container..."
docker compose start web

echo "$(date): Demo reset complete!"
