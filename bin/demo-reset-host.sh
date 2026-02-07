#!/bin/bash
set -euo pipefail

# Demo reset script for the HOST machine (outside container)
# Copy this to /opt/sabha/demo-reset.sh on the demo server
#
# Cron: 0 * * * * /opt/sabha/demo-reset.sh >> /var/log/demo-reset.log 2>&1
#
# Note: Demo servers don't have litestream (backups disabled), so we only
# need to stop/start the web container.

cd /opt/sabha

echo "$(date): Starting demo reset..."

# Stop the web container
echo "$(date): Stopping web container..."
docker compose stop web

# Copy snapshot over production database, fix ownership, and remove WAL files
echo "$(date): Restoring database from snapshot..."
docker run --rm -v sabha_sabha_data:/rails/storage alpine sh -c "
  rm -f /rails/storage/db/production.sqlite3-wal /rails/storage/db/production.sqlite3-shm
  cp /rails/storage/db/demo_snapshot.sqlite3 /rails/storage/db/production.sqlite3
  chown 999:999 /rails/storage/db/production.sqlite3
"

# Start the web container
echo "$(date): Starting web container..."
docker compose start web

echo "$(date): Demo reset complete!"
