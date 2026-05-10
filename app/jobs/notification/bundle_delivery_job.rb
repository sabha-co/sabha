# Re-runs eligibility at delivery time so state changes during the bundle
# window (block, deactivation, settings flip, return-from-away) drop items
# that were eligible at dispatch time. Empty bundles cancel without sending.
class Notification::BundleDeliveryJob < ApplicationJob
  # Distinguishes "bundle canceled because the address is unreachable" from
  # transient infrastructure flakes that Solid Queue should retry.
  TerminalError = Class.new(StandardError)

  discard_on ActiveJob::DeserializationError

  def perform(bundle)
    return if DemoMode.enabled?
    return if bundle.terminal?

    eligible_items = revalidate(bundle)

    if eligible_items.empty?
      bundle.cancel!
      return
    end

    deliver(bundle, eligible_items)
  end

  private
    # Bundles span multiple rooms but always one user, so memberships are
    # looked up per (room_id, user_id) pair with the user fixed.
    def revalidate(bundle)
      items = bundle.items.includes(:message, :actor).to_a
      return items if items.empty?

      room_ids = items.map { |i| i.message.room_id }.uniq
      memberships_by_room = Membership.where(room_id: room_ids, user_id: bundle.user_id).index_by(&:room_id)

      items.select do |item|
        membership = memberships_by_room[item.message.room_id]
        membership && membership.receives_missed_email_for?(item.message, item.kind.to_sym)
      end
    end

    def deliver(bundle, items)
      MissedNotificationsMailer.bundle(bundle, items).deliver_now
      bundle.mark_delivered!
    rescue *terminal_error_classes => error
      bundle.cancel!
      raise TerminalError, "Bundle ##{bundle.id} canceled: #{error.class}: #{error.message}"
    end

    # 4xx-except-429 Resend errors and SES rejections are non-retryable —
    # canceling the bundle is the only sane action. Transient errors (5xx,
    # rate limits, timeouts) propagate so Solid Queue retries.
    def terminal_error_classes
      classes = [ Resend::Error::InvalidRequestError ]
      if defined?(Aws::SESV2::Errors)
        classes << Aws::SESV2::Errors::MessageRejected
        classes << Aws::SESV2::Errors::MailFromDomainNotVerified
      end
      classes
    end
end
