Rails.application.config.to_prepare do
  GumroadAPI.access_token = ENV["GUMROAD_ACCESS_TOKEN"]
end
