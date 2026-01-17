# AnyCable Implementation Plan

This document outlines the plan to add AnyCable support to campfire-ce for improved WebSocket scalability.

## Problem

Rails Action Cable has significant scalability limitations for real-time chat applications.

## Load Test Results

Load tests conducted on a 1 vCPU / 2GB DigitalOcean droplet with 500 concurrent users:

| Metric | Action Cable | AnyCable | Improvement |
|--------|-------------|----------|-------------|
| **WebSocket connect time (avg)** | 7.33s | 43.82ms | **167x faster** |
| **Messages received** | 7,133 | 17,553 | **2.5x more** |
| **Messages/second** | 358/s | 714/s | **2x throughput** |
| **Subscriptions confirmed** | 3,000 | 3,000 | Same |
| **Data received** | 154 MB | 379 MB | 2.5x |

### Test Configuration

- **Server**: DigitalOcean 1 vCPU / 2GB RAM (ubuntu-s-1vcpu-2gb)
- **Users**: 500 concurrent WebSocket connections
- **Channels per user**: 6 (PresenceChannel, UnreadRoomsChannel, HeartbeatChannel, 3x Turbo::StreamsChannel)
- **Test duration**: 60 seconds
- **Tool**: k6 with custom chatter.js script

### Running Load Tests

```bash
# Test Action Cable
bin/load-anycable -h server.example.com --ssh-user root -u 500

# Test AnyCable
bin/load-anycable -h server.example.com --ssh-user root -u 500 --anycable
```

See `bin/load-anycable --help` for all options

## Solution: HTTP RPC Mode

AnyCable offers multiple RPC modes. We'll use **HTTP RPC** as the simplest approach:

- No gRPC dependencies
- No separate RPC process
- Rails mounts an HTTP endpoint that AnyCable-Go calls
- Minimal configuration

### Architecture

**Before (Action Cable):**
```
┌─────────────────────────────────────────────────────┐
│                   campfire-ce instance              │
│  ┌──────────┐   ┌────────────────┐   ┌───────────┐ │
│  │  Caddy   │──▶│  campfire-web  │   │ Litestream│ │
│  │  :443    │   │   Rails+Redis  │   │  backup   │ │
│  └──────────┘   │   ActionCable  │   └───────────┘ │
│                 │     :3000      │                  │
│                 └────────────────┘                  │
└─────────────────────────────────────────────────────┘
```

**After (AnyCable):**
```
┌──────────────────────────────────────────────────────────────┐
│                     campfire-ce instance                     │
│                                                              │
│  ┌────────┐   /cable    ┌─────────────┐                     │
│  │ Caddy  │────────────▶│ anycable-go │                     │
│  │  :443  │             │    :8080    │                     │
│  │        │   /*        │             │                     │
│  │        │────────┐    └──────┬──────┘                     │
│  └────────┘        │           │                            │
│                    │           │ HTTP RPC (/_anycable)      │
│                    │           │ HTTP Broadcast (/_broadcast)│
│                    │           ▼                            │
│                    │    ┌────────────────┐   ┌───────────┐  │
│                    └───▶│  campfire-web  │   │ Litestream│  │
│                         │  Rails :3000   │   │  backup   │  │
│                         └────────────────┘   └───────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **WebSocket Connection**: Client connects to `wss://domain.com/cable`
2. **Caddy Routing**: Routes `/cable` to `anycable-go:8080`
3. **Authentication**: AnyCable-Go calls Rails at `/_anycable` to authenticate
4. **Channel Subscription**: AnyCable-Go calls Rails RPC for channel logic (subscribe/unsubscribe)
5. **Broadcasting**: Rails broadcasts via HTTP to AnyCable-Go at `/_broadcast`
6. **Message Delivery**: AnyCable-Go pushes to connected WebSocket clients

## Development Testing

Test AnyCable changes locally before deploying to production.

### Step 1: Install AnyCable-Go Binary

```bash
# macOS (Homebrew)
brew install anycable-go

# Or download directly
curl -fsSL https://github.com/anycable/anycable-go/releases/download/v1.6.3/anycable-go-darwin-arm64 -o /usr/local/bin/anycable-go
chmod +x /usr/local/bin/anycable-go

# Verify installation
anycable-go --version
```

### Step 2: Add AnyCable Gem

```bash
cd /path/to/campfire-ce
# Use anycable-rails-core to avoid gRPC dependency (HTTP RPC mode doesn't need it)
bundle add anycable-rails-core
```

### Step 3: Create Configuration Files

**config/anycable.yml:**
```yaml
default: &default
  # Mount HTTP RPC endpoint in Rails
  http_rpc_mount_path: "/_anycable"

  # Use HTTP for broadcasting
  broadcast_adapter: http
  http_broadcast_url: "http://localhost:8080/_broadcast"

development:
  <<: *default
  websocket_url: "ws://localhost:8080/cable"
  secret: "development-secret-change-in-production"

test:
  <<: *default
  secret: "test-secret"

production:
  <<: *default
  websocket_url: <%= "wss://#{ENV['APP_HOST']}/cable" %>
  secret: <%= ENV["ANYCABLE_SECRET"] %>
```

### Step 4: Update Cable Configuration

**config/cable.yml:**
```yaml
default: &default
  adapter: redis
  url: redis://localhost:6379

development:
  adapter: <%= ENV["ANYCABLE_ENABLED"] == "false" ? "redis" : "any_cable" %>
  <% if ENV["ANYCABLE_ENABLED"] == "false" %>
  url: redis://localhost:6379
  channel_prefix: campfire_development
  <% end %>

test:
  adapter: test

production:
  adapter: <%= ENV["ANYCABLE_ENABLED"] == "false" ? "redis" : "any_cable" %>
  <% if ENV["ANYCABLE_ENABLED"] == "false" %>
  url: <%= ENV.fetch("REDIS_URL", "redis://localhost:6379") %>
  channel_prefix: campfire_production
  <% end %>
```

AnyCable is enabled by default. Set `ANYCABLE_ENABLED=false` to use standard ActionCable with Redis.

### Step 5: Update Procfile.dev

**Procfile.dev:**
```
vite: bin/vite dev
web: PORT=3000 bin/rails s
anycable: anycable-go --port=8080 --rpc_host=http://localhost:3000/_anycable --broadcast_adapter=http --secret=development-secret-change-in-production
```

### Step 6: Update JavaScript WebSocket URL

The JavaScript client needs to connect to AnyCable instead of Rails. Check if the WebSocket URL is hardcoded or uses the meta tag.

**app/views/layouts/application.html.erb:**
```erb
<%# Ensure this meta tag is present - it tells ActionCable JS where to connect %>
<%= action_cable_meta_tag %>
```

**app/frontend/entrypoints/application.js** (if WebSocket URL is configured):
```javascript
// If you have custom ActionCable configuration, update the URL:
// In development, this should point to AnyCable-Go at ws://localhost:8080/cable
// The action_cable_meta_tag helper handles this automatically
```

### Step 7: Run Development Server

```bash
# Terminal 1: Start all services with foreman/overmind
bin/rails dev

# Or run each process manually:
# Terminal 1: Rails
bin/rails s

# Terminal 2: Vite
bin/vite dev

# Terminal 3: AnyCable-Go
anycable-go --port=8080 \
  --rpc_host=http://localhost:3000/_anycable \
  --broadcast_adapter=http \
  --secret=development-secret-change-in-production \
  --log_level=debug
```

### Step 8: Verify It's Working

1. **Check AnyCable-Go started:**
   ```
   INFO 2024-01-01T00:00:00.000Z context=main Starting AnyCable 1.6.3
   INFO 2024-01-01T00:00:00.000Z context=main Handle WebSocket connections at http://localhost:8080/cable
   INFO 2024-01-01T00:00:00.000Z context=http RPC server endpoint: http://localhost:3000/_anycable
   ```

2. **Open browser console**, navigate to a room, check WebSocket connection:
   ```
   // Should see connection to ws://localhost:8080/cable instead of ws://localhost:3000/cable
   ```

3. **Test real-time features:**
   - Open two browser windows to the same room
   - Send a message - should appear in both windows
   - Start typing - typing indicator should appear
   - Check presence (user online/offline status)

4. **Check AnyCable logs for RPC calls:**
   ```
   DEBUG context=rpc RPC Connect: {"user_id": 1}
   DEBUG context=rpc RPC Subscribe: {"channel": "RoomChannel", "room_id": 1}
   ```

### Step 9: Run Tests

```bash
# Run the full test suite to ensure nothing broke
bin/rails test

# Run system tests (these test real WebSocket behavior)
bin/rails test:system
```

### Troubleshooting Development Setup

**WebSocket still connecting to Rails (port 3000):**
- Check `action_cable_meta_tag` is in your layout
- Verify `config/anycable.yml` has correct `websocket_url` for development
- Clear browser cache / hard refresh

**RPC connection refused:**
- Ensure Rails is running and accessible at localhost:3000
- Check `http_rpc_mount_path: "/_anycable"` is set
- Test RPC endpoint: `curl http://localhost:3000/_anycable` (should return error about missing headers, not 404)

**Broadcasts not working:**
- Verify `broadcast_adapter: http` in anycable.yml
- Check AnyCable-Go is receiving broadcasts: look for `broadcast` in debug logs
- Ensure `http_broadcast_url` points to AnyCable-Go

**Channel subscription rejected:**
- Check Rails logs for authentication errors
- Verify the user is logged in
- Check channel authorization logic in `RoomChannel#find_room`

---

## Standalone Deployment

By default, campfire-ce uses **AnyCable** for WebSocket connections in production. This requires:

1. **anycable-go container** running alongside the Rails app
2. **Proxy routing** to send `/cable` requests to anycable-go
3. **ANYCABLE_SECRET** environment variable set in both containers

### Kamal Deployment

The included `config/deploy.yml` sets up AnyCable with a WebSocket subdomain.
See the [AnyCable Kamal Guide](https://github.com/anycable/docs.anycable.io/blob/master/docs/deployment/kamal.md) for detailed configuration options.

1. **Add DNS record**: Point `ws.yourdomain.com` to your server IP
2. **Set secrets** in `.kamal/secrets`:
   ```bash
   ANYCABLE_SECRET=your-random-secret-here
   ```
3. **Deploy**: `kamal setup` will deploy both web and anycable containers

Clients connect to `wss://ws.yourdomain.com/cable` for WebSocket.

### campfire_cloud Deployment

campfire_cloud uses Caddy for path-based routing (`/cable` → anycable). Set these environment variables:

```bash
ANYCABLE_WEBSOCKET_URL=wss://yourdomain.com/cable
ANYCABLE_BROADCAST_URL=http://anycable:8080/_broadcast
```

### Docker Compose Example

```yaml
services:
  web:
    image: ghcr.io/superforumio/campfire-ce:latest
    environment:
      # AnyCable is enabled by default (ANYCABLE_ENABLED != "false")
      - ANYCABLE_SECRET=${ANYCABLE_SECRET}
    networks:
      - campfire

  anycable:
    image: anycable/anycable-go:1.6
    environment:
      - ANYCABLE_HOST=0.0.0.0
      - ANYCABLE_PORT=8080
      - ANYCABLE_RPC_HOST=http://web:3000/_anycable
      - ANYCABLE_BROADCAST_ADAPTER=http
      - ANYCABLE_HTTP_BROADCAST_PORT=8080
      - ANYCABLE_SECRET=${ANYCABLE_SECRET}
    networks:
      - campfire

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
    networks:
      - campfire

networks:
  campfire:
```

**Caddyfile:**
```
example.com {
    handle /cable {
        reverse_proxy anycable:8080
    }
    handle {
        reverse_proxy web:3000
    }
}
```

---

## Configuration Reference

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANYCABLE_SECRET` | Shared secret for auth and signing (required) | - |
| `ANYCABLE_LOG_LEVEL` | Log verbosity (debug/info/warn/error) | info |

### AnyCable-Go Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `ANYCABLE_HOST` | 0.0.0.0 | Listen on all interfaces |
| `ANYCABLE_PORT` | 8080 | WebSocket server port |
| `ANYCABLE_RPC_HOST` | http://web:3000/_anycable | Rails RPC endpoint |
| `ANYCABLE_BROADCAST_ADAPTER` | http | Use HTTP for broadcasts |
| `ANYCABLE_HTTP_BROADCAST_PORT` | 8080 | Broadcast receiver port |

## Monitoring

### Health Checks

- **AnyCable-Go**: `GET /health` on port 8080
- **Rails RPC**: Responds at `/_anycable` (internal)

### Metrics (Future)

AnyCable-Go exposes Prometheus metrics at `/metrics`:
- `anycable_clients_num` - Current connected clients
- `anycable_clients_total` - Total connections
- `anycable_broadcast_msg_total` - Broadcast messages
- `anycable_rpc_call_total` - RPC calls to Rails

## Troubleshooting

### Common Issues

**WebSocket connection fails:**
1. Check Caddy logs for routing issues
2. Verify AnyCable container is healthy
3. Check `ANYCABLE_SECRET` matches in both containers

**Channel subscriptions fail:**
1. Check AnyCable logs for RPC errors
2. Verify Rails is responding at `/_anycable`
3. Check Rails logs for authentication issues

**Broadcasts not received:**
1. Verify `broadcast_adapter: http` in anycable.yml
2. Check AnyCable-Go is receiving at `/_broadcast`
3. Verify client is subscribed to correct channel

### Debug Mode

Enable verbose logging:
```yaml
environment:
  - ANYCABLE_LOG_LEVEL=debug
  - ANYCABLE_DEBUG=true
```

## Resources

- [AnyCable Documentation](https://docs.anycable.io/)
- [AnyCable Rails Guide](https://docs.anycable.io/rails/getting_started)
- [AnyCable Kamal Deployment](https://github.com/anycable/docs.anycable.io/blob/master/docs/deployment/kamal.md)
- [HTTP RPC Documentation](https://docs.anycable.io/ruby/http_rpc)
- [Real-time Stress: AnyCable, k6, WebSockets](https://evilmartians.com/chronicles/real-time-stress-anycable-k6-websockets-and-yabeda) - Load testing guide with xk6-cable
