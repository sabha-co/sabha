# Print boot mode for clarity during development
Rails.application.config.after_initialize do
  mode = Campfire.saas? ? "SaaS (multi-tenant)" : "Single-tenant"

  if Rails.env.local?
    puts ""
    puts "  Campfire running in #{mode} mode"
    puts ""
  else
    Rails.logger.info "[Campfire] Running in #{mode} mode"
  end
end
