# Single dispatch entry point for notifications across channels (in-app rows,
# push, missed-notification email bundle candidates). One job per message; the
# boost path is the only call site that uses `only:`.
class Notification::DispatchJob < ApplicationJob
  discard_on ActiveJob::DeserializationError::RecordNotFound

  def perform(message, only: nil, actor: nil)
    return if DemoMode.enabled?
    message.notify_recipients(only: only, actor: actor)
  end
end
