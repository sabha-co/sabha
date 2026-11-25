Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/models/channels/*.rb")].each { |file| require file }
end if Rails.env.development?
