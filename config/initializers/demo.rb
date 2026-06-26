# Demo mode configuration
#
# Set DEMO_MODE=true to enable demo mode features:
# - Disables email sending
# - Disables webhook deliveries
# - Disables push notifications
# - Shows demo banner in footer
# - Shows login credentials on sign-in page
#
# For resets every 3 hours, add to crontab:
#   0 */3 * * * cd /app && bin/demo-reset

module DemoMode
  def self.enabled?
    ENV["DEMO_MODE"] == "true"
  end

  def self.credentials
    {
      email: "admin@sabha.co",
      password: "password"
    }
  end

  def self.reset_interval
    "every 3 hours"
  end
end
