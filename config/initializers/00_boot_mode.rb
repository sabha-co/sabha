# Boot-time validation of required environment variables per deployment mode.
#
# Three deployment modes:
#   Self-hosted (default) — customer runs Sabha via Docker/Kamal
#   SaaS (SAAS=true)      — multi-tenant sabha.co
#   Managed               — sabha_cloud deploys for customers (AUTO_BOOTSTRAP=true,
#                           bootstraps the first admin via an SSO round-trip)
#
# Catches misconfigured deploys at boot instead of silently producing
# broken WebSocket URLs, mailer configs, etc.

if Sabha.saas? && ENV["AUTH_METHOD"].in?(%w[password sso])
  abort "FATAL: AUTH_METHOD=#{ENV['AUTH_METHOD']} is not supported in SaaS mode. SaaS uses OTP-only authentication via GlobalIdentity."
end

# AnyCable is required. The in-process ActionCable fallback was removed, so
# ANYCABLE_ENABLED=false has nothing left to fall back to — fail loudly on boot
# rather than silently degrading a holdout's real-time layer.
if ENV["ANYCABLE_ENABLED"] == "false"
  abort "FATAL: ANYCABLE_ENABLED=false is no longer supported — AnyCable is required. Remove ANYCABLE_ENABLED from your environment and run the anycable-go accessory."
end

if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"].present?
  # ANYCABLE_SECRET has always been required for RPC and JWT signing, but a
  # blank one used to fail loudly at the first WebSocket. Push gating now
  # derives the presence API secret from it, and anycable-go *disables* its API
  # when no secret is set — so a blank value would instead degrade every
  # presence read to "broker unavailable" and quietly push members who are
  # sitting in the room reading. Fail here instead.
  required = %w[APP_HOST SECRET_KEY_BASE ANYCABLE_SECRET]

  if Sabha.saas?
    required += %w[COOKIE_DOMAIN UNTENANTED_DATABASE_URL]
  end

  if ENV["AUTO_BOOTSTRAP"] == "true"
    required += %w[SSO_PROVIDER_URL SSO_SECRET]
  end

  missing = required.select { |key| ENV[key].blank? }
  abort "FATAL: Missing required environment variables: #{missing.join(', ')}" if missing.any?
end

Rails.application.config.after_initialize do
  mode = if Sabha.saas?
    "SaaS (multi-tenant)"
  elsif ENV["AUTO_BOOTSTRAP"] == "true"
    "Managed"
  else
    "Single-tenant"
  end

  if Rails.env.local?
    puts ""
    puts "  Sabha running in #{mode} mode"
    puts ""
  else
    Rails.logger.info "[Sabha] Running in #{mode} mode"
  end
end
