RailsCloudflareTurnstile.configure do |c|
  is_asset_precompile = ENV["SECRET_KEY_BASE_DUMMY"].present?

  c.site_key = ENV["CLOUDFLARE_TURNSTILE_SITE_KEY"] ||
    (Rails.env.local? || is_asset_precompile ? "1x00000000000000000000AA" : nil)

  c.secret_key = ENV["CLOUDFLARE_TURNSTILE_SECRET_KEY"] ||
    (Rails.env.local? || is_asset_precompile ? "1x0000000000000000000000000000000AA" : nil)

  # SaaS: always enabled in production
  # Self-hosted: only enabled when keys are configured
  c.enabled = Rails.env.production? && !is_asset_precompile && c.site_key.present?

  c.fail_open = Rails.env.production?
  c.mock_enabled = Rails.env.local? || is_asset_precompile
  c.theme = :light
end
