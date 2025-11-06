require "rufus-scheduler"

Rails.application.config.after_initialize do
  if Rails.env.production? && defined?(Rails::Server) && !defined?($rufus_scheduler)
    Rails.logger.info "Starting Rufus scheduler."
    $rufus_scheduler = Rufus::Scheduler.new

    $rufus_scheduler.cron "0 9,18 * * * America/Los_Angeles" do
      UnreadMentionsNotifierJob.new.perform
    end
  end
end
