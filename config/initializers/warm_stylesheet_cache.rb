Rails.application.config.after_initialize do
  if defined?(Stylesheets)
    Rails.logger.info "Warming stylesheet cache..."

    Stylesheets.from("application")
    Stylesheets.vendor_stylesheets

    Rails.logger.info "Stylesheet cache warmed"
  end
end
