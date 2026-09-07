class ApplicationMailer < ActionMailer::Base
  # Set on mail a script asked for (a headless browser signing in, say) so the
  # development preview can stay out of the browser of the person at the desk.
  AUTOMATED_CLIENT_HEADER = "X-Sabha-Automated-Client"

  default from: -> { Branding.mailer_from },
          "X-SES-DISABLE-TRACKING" => "true"
  layout "mailer"

  # Discard mail deliveries targeting a deleted workspace (tenant DB no longer exists)
  rescue_from "ActiveRecord::Tenanted::TenantDoesNotExistError" do; end if defined?(ActiveRecord::Tenanted)


  before_action :skip_in_demo_mode

  helper_method :formatted_time

  def formatted_time(time)
    time&.strftime("%b %-d, %-I:%M %p")
  end

  private
    def mark_automated_client(automated)
      headers[AUTOMATED_CLIENT_HEADER] = "true" if automated
    end

    def skip_in_demo_mode
      mail.perform_deliveries = false if DemoMode.enabled?
    end
end
