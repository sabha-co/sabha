# Single dispatch entry point for notifications across channels (in-app rows,
# push, missed-notification email bundle candidates). One job per message; the
# boost path is the only call site that uses `only:`.
#
# Substance lives on `Message#notify_recipients`. This job is a shallow wrapper
# so ActiveJob serializes a Message GlobalID and the gem belt-and-suspenders
# carries tenant context.
#
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 5.
class Notification::DispatchJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(message, only: nil, actor: nil)
    return if DemoMode.enabled?
    message.notify_recipients(only: only, actor: actor)
  end
end
