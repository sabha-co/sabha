# Boot-time validation of required environment variables per deployment mode.
#
# Three deployment modes:
#   Self-hosted (default) — customer runs Sabha via Docker/Kamal
#   SaaS (SAAS=true)      — multi-tenant sabha.co
#   Managed               — campfire_cloud deploys for customers (AUTO_BOOTSTRAP=true)
#
# Catches misconfigured deploys at boot instead of silently producing
# broken WebSocket URLs, mailer configs, etc.

if Sabha.saas? && ENV["AUTH_METHOD"] == "password"
  abort "FATAL: AUTH_METHOD=password is not supported in SaaS mode. SaaS uses OTP-only authentication via GlobalIdentity."
end

if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"].present?
  required = %w[APP_HOST SECRET_KEY_BASE]

  if Sabha.saas?
    required += %w[COOKIE_DOMAIN UNTENANTED_DATABASE_URL SAAS_MAILER_FROM_EMAIL]
  end

  if ENV["AUTO_BOOTSTRAP"] == "true"
    required += %w[ADMIN_EMAIL ADMIN_AUTH_TOKEN]
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
