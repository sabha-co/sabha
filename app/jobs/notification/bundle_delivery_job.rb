# Re-runs eligibility at delivery time so state changes during the bundle
# window (block, deactivation, settings flip, return-from-away) drop items
# that were eligible at dispatch time. Empty bundles cancel without sending.
class Notification::BundleDeliveryJob < ApplicationJob
  # Distinguishes "bundle canceled because the address is unreachable" from
  # transient infrastructure flakes that Solid Queue should retry.
  TerminalError = Class.new(StandardError)

  discard_on ActiveJob::DeserializationError
  # The bundle is already canceled by the time we raise TerminalError. Discard
  # so Solid Queue closes the job cleanly instead of recording a failed
  # execution that operators would investigate (the work is done).
  discard_on TerminalError

  # Transient errors propagate via Active Job's retry_on so Solid Queue
  # re-runs the job. Resend dedups duplicate sends via the X-Idempotency-Key
  # header set by MissedNotificationsMailer. SES has no equivalent per-call
  # idempotency parameter — a worker crash between deliver_now success and
  # mark_delivered! commit will produce a duplicate inbox on retry. Operators
  # using SES should pair this job with an SES configuration set that has
  # message-id-based deduplication enabled.
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
           wait: :polynomially_longer, attempts: 5
  retry_on Resend::Error::RateLimitExceededError, Resend::Error::InternalServerError,
           wait: :polynomially_longer, attempts: 5
  if defined?(Aws::SESV2::Errors)
    retry_on Aws::SESV2::Errors::ThrottlingException, Aws::SESV2::Errors::TooManyRequestsException,
             wait: :polynomially_longer, attempts: 5
  end

  def perform(bundle)
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
      items = bundle.items.includes(:actor, message: [ :room, :rich_text_body ]).to_a
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
      finalize_delivery(bundle, items.map(&:id))
    rescue *terminal_error_classes => error
      bundle.cancel!
      raise TerminalError, "Bundle ##{bundle.id} canceled: #{error.class}: #{error.message}"
    end

    # Items inserted during deliver_now would be stranded on a delivered bundle
    # (the dispatcher had this bundle in memory as active). Atomically mark this
    # bundle delivered and migrate any leftover items onto a fresh active
    # bundle, which schedules its own delivery. The partial unique index
    # prevents two active bundles per user, so mark_delivered! must come before
    # open_notification_bundle!.
    def finalize_delivery(bundle, delivered_item_ids)
      Notification::Bundle.transaction do
        bundle.mark_delivered!

        leftover_item_ids = bundle.items.where.not(id: delivered_item_ids).pluck(:id)
        next if leftover_item_ids.empty?

        next_bundle = bundle.user.open_notification_bundle!
        Notification::BundleItem.where(id: leftover_item_ids).update_all(bundle_id: next_bundle.id)
        next_bundle.schedule_delivery
      end
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
