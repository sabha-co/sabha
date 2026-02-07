# Print boot mode for clarity during development
Rails.application.config.after_initialize do
  mode = Sabha.saas? ? "SaaS (multi-tenant)" : "Single-tenant"

  if Rails.env.local?
    puts ""
    puts "  Sabha running in #{mode} mode"
    puts ""
  else
    Rails.logger.info "[Sabha] Running in #{mode} mode"
  end
end
