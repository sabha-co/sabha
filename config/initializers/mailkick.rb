Mailkick.secret_token = Rails.application.secret_key_base
Mailkick.headers = true

# Configure Mailkick::Subscription as a subtenant in SaaS mode
# This ensures subscription queries use the correct tenant database
if Sabha.saas?
  Rails.application.config.to_prepare do
    Mailkick::Subscription.subtenant_of "ApplicationRecord"
  end
end
