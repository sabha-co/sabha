#!/bin/bash
set -e

echo "🚀 Deploying Campfire-CE with Docker Compose..."

cd /opt/campfire

# Pull new image
echo "📥 Pulling latest image..."
docker-compose pull web

# Stop old container
echo "🛑 Stopping old container..."
docker-compose stop web || true

# Start all services (web and caddy)
echo "✅ Starting services..."
docker-compose up -d

# Run migrations if needed
echo "🗄️  Running migrations..."
docker-compose exec -T web bin/rails db:migrate

# Health check
echo "🏥 Waiting for health check..."
sleep 15

if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    echo "✅ Deployment successful!"
else
    echo "❌ Health check failed!"
    docker-compose logs --tail=50 web
    exit 1
fi

# Show recent logs
echo ""
echo "📋 Recent logs:"
docker-compose logs --tail=30 web
