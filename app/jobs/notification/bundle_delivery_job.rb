# Delivers a Notification::Bundle when its window closes. Walks bundle items,
# re-runs the receives_missed_email_for? predicate at delivery time so state
# changes (block, deactivation, settings flip, return-from-away) drop items
# that were eligible at dispatch time. If all items drop, cancels the bundle
# without sending. Otherwise, hands off to MissedNotificationsMailer with a
# stable provider-side idempotency key.
#
# See docs/plans/NOTIFICATIONS-ARCHITECTURE.md § 7.3 and § 7.5.
class Notification::BundleDeliveryJob < ApplicationJob
  # Re-raised on terminal provider errors (arch § 14.1) so observability tools
  # can distinguish "bundle canceled because the address is unreachable" from
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
    # Reload items eagerly with the rows we need for revalidation and
    # rendering. Memberships are looked up per (room_id, user_id) pair —
    # bundles span multiple rooms but always one user, so the user is fixed.
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
