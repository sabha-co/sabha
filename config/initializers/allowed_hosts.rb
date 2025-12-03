# Configure allowed hosts for DNS rebinding protection
# This allows the application to accept requests from configured domains
#
# Environment Variables:
#   APP_HOST - Primary domain (e.g., "chat.example.com")
#   ALLOWED_HOSTS - Comma-separated list of additional allowed domains
#                   (e.g., "chat.example.com,chat-backup.example.com")
#
# Examples:
#   # Single domain
#   APP_HOST=chat.example.com
#   => Allows: chat.example.com
#
#   # Multiple domains (e.g., with custom domain)
#   APP_HOST=chat.example.com
#   ALLOWED_HOSTS=chat.example.com,mycustomdomain.com
#   => Allows: chat.example.com, mycustomdomain.com
#
#   # Allow all hosts (not recommended for production)
#   ALLOWED_HOSTS=
#   => Allows: all hosts

Rails.application.configure do
  # In development/test, allow localhost by default
  if Rails.env.development? || Rails.env.test?
    config.hosts << "localhost"
    config.hosts << "127.0.0.1"
  end

  # Get the primary APP_HOST
  app_host = ENV["APP_HOST"]

  # Add APP_HOST if present
  config.hosts << app_host if app_host.present?

  # Allow additional hosts from ALLOWED_HOSTS environment variable (comma-separated)
  if ENV["ALLOWED_HOSTS"].present?
    additional_hosts = ENV["ALLOWED_HOSTS"].split(",").map(&:strip).reject(&:blank?)
    additional_hosts.each { |host| config.hosts << host }
  end

  # Log the allowed hosts for debugging in non-production environments
  unless Rails.env.production?
    Rails.logger.info("Allowed hosts configured: #{config.hosts.inspect}")
  end
end
