session_options = {
  key: "_sabha_session",
  # Persist session cookie as permament so re-opened browser windows maintain a CSRF token
  expire_after: 20.years
}

if Sabha.saas?
  # Self-hosted workspaces can live on the SaaS domain's subdomains (a demo, a
  # Sabha Cloud server), and they use _sabha_session too. So the SaaS session
  # gets its own name and stays on its own host, or it would shadow theirs.
  session_options[:key] = "_sabha_saas_session"
elsif ENV["COOKIE_DOMAIN"].present?
  # Only set domain if COOKIE_DOMAIN is present (avoid nil which causes Rack errors)
  session_options[:domain] = ENV["COOKIE_DOMAIN"]
end

Rails.application.config.session_store :cookie_store, **session_options
