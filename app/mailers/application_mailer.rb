class ApplicationMailer < ActionMailer::Base
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
    def skip_in_demo_mode
      mail.perform_deliveries = false if DemoMode.enabled?
    end
end
