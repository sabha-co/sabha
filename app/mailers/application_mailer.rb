class ApplicationMailer < ActionMailer::Base
  default from: -> { Branding.mailer_from }
  layout "mailer"

  helper_method :formatted_time

  def formatted_time(time)
    time&.strftime("%b %-d, %-I:%M %p")
  end
end
