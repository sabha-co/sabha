require "test_helper"

class Notification::BundleDeliveryJobTest < ActiveSupport::TestCase
  setup do
    @user    = users(:jason)
    @actor   = users(:david)
    @room    = rooms(:designers)
    @user.notification_settings&.update!(missed_email_enabled: true) ||
      @user.create_notification_settings!(missed_email_enabled: true)
    Account.sole.update!(email_notifications_enabled: true)

    @bundle = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )
  end

  test "delivers the bundle and marks it delivered when items remain eligible" do
    item = create_item!(create_message!)

    expect_mailer_delivery(@bundle, [ item ])

    Notification::BundleDeliveryJob.perform_now(@bundle)

    assert @bundle.reload.delivered_at.present?
    assert_nil @bundle.canceled_at
  end

  test "drops items the predicate rejects at delivery time, delivers the rest" do
    keeper = create_item!(create_message!(body: "<div>still here #{mention_attachment_for(:jason)}</div>"))
    dropped_message = create_message!(body: "<div>blocked sender #{mention_attachment_for(:jason)}</div>")
    create_item!(dropped_message)

    # Block the sender mid-window — predicate should reject the dropped item only.
    @user.block!(@actor)
    # Even with block, the keeper goes through because the predicate is checked
    # against ITS message and the block applies equally — so we need a more
    # selective drop. Instead: deactivate one message.
    @user.unblock!(@actor)
    dropped_message.deactivate!

    delivered_items = nil
    expect_mailer do |_bundle, items|
      delivered_items = items
    end

    Notification::BundleDeliveryJob.perform_now(@bundle)

    assert_equal [ keeper.id ], delivered_items.map(&:id)
    assert @bundle.reload.delivered_at.present?
  end

  test "cancels the bundle without sending when all items drop" do
    msg = create_message!
    create_item!(msg)
    msg.deactivate!

    MissedNotificationsMailer.expects(:bundle).never

    Notification::BundleDeliveryJob.perform_now(@bundle)

    assert @bundle.reload.canceled_at.present?
    assert_nil @bundle.delivered_at
  end

  test "skips delivery when bundle is already terminal" do
    create_item!(create_message!)
    @bundle.update!(delivered_at: Time.current)

    MissedNotificationsMailer.expects(:bundle).never

    Notification::BundleDeliveryJob.perform_now(@bundle)
  end

  test "discards on DeserializationError when the bundle has been deleted" do
    assert_enqueued_with(job: Notification::BundleDeliveryJob) do
      Notification::BundleDeliveryJob.perform_later(@bundle)
    end

    @bundle.destroy!

    # Perform the enqueued job after the underlying record is gone. The
    # discard_on ActiveJob::DeserializationError declaration must swallow the
    # GlobalID lookup failure so the queue closes cleanly instead of retrying.
    MissedNotificationsMailer.expects(:bundle).never
    assert_nothing_raised do
      perform_enqueued_jobs(only: Notification::BundleDeliveryJob)
    end
  end

  test "cancels the bundle and discards on a Resend 4xx error" do
    create_item!(create_message!)
    MissedNotificationsMailer.expects(:bundle).raises(Resend::Error::InvalidRequestError.new("bad address", 422))

    # TerminalError is discarded so Solid Queue closes cleanly; the cancellation
    # is what operators see, not a failed execution.
    assert_nothing_raised do
      Notification::BundleDeliveryJob.perform_now(@bundle)
    end
    assert @bundle.reload.canceled_at.present?
    assert_nil @bundle.delivered_at
  end

  test "cancels the bundle and discards on a Resend 404 not-found error" do
    create_item!(create_message!)
    # Resend 1.7 remapped 404 from InvalidRequestError to NotFoundError; both are
    # non-retryable 4xx failures, so the bundle must still cancel rather than fail.
    MissedNotificationsMailer.expects(:bundle).raises(Resend::Error::NotFoundError.new("not found", 404))

    assert_nothing_raised do
      Notification::BundleDeliveryJob.perform_now(@bundle)
    end
    assert @bundle.reload.canceled_at.present?
    assert_nil @bundle.delivered_at
  end

  test "transient provider errors are retried, not canceled" do
    create_item!(create_message!)
    MissedNotificationsMailer.expects(:bundle).raises(Resend::Error::InternalServerError.new("oops", 500))

    assert_enqueued_with(job: Notification::BundleDeliveryJob) do
      Notification::BundleDeliveryJob.perform_now(@bundle)
    end

    assert_nil @bundle.reload.delivered_at, "transient errors must not mark the bundle delivered"
    assert_nil @bundle.canceled_at,           "transient errors must not cancel the bundle"
  end

  test "transient network timeouts are retried, not canceled" do
    create_item!(create_message!)
    MissedNotificationsMailer.expects(:bundle).raises(Net::OpenTimeout)

    assert_enqueued_with(job: Notification::BundleDeliveryJob) do
      Notification::BundleDeliveryJob.perform_now(@bundle)
    end

    assert_nil @bundle.reload.delivered_at
    assert_nil @bundle.canceled_at
  end

  private
    def create_message!(body: "<div>hello #{mention_attachment_for(:jason)}</div>", room: @room)
      room.messages.create!(body: body, creator: @actor, client_message_id: "u6_dlv_#{SecureRandom.hex(4)}")
    end

    def create_item!(message, kind: "mention")
      Notification::BundleItem.create!(bundle: @bundle, message: message, actor: @actor, kind: kind)
    end

    def expect_mailer_delivery(bundle, expected_items)
      mail = mock("mail")
      mail.expects(:deliver_now).once
      MissedNotificationsMailer.expects(:bundle).with do |b, items|
        assert_equal bundle.id, b.id
        assert_equal expected_items.map(&:id).sort, items.map(&:id).sort
        items.each do |item|
          assert item.association(:actor).loaded?, "actor should be preloaded for mail rendering"
          assert item.association(:message).loaded?, "message should be preloaded for mail rendering"
          assert item.message.association(:room).loaded?, "message room should be preloaded for mail rendering"
          assert item.message.association(:rich_text_body).loaded?, "message body should be preloaded for previews"
        end
        true
      end.returns(mail)
    end

    def expect_mailer(&block)
      mail = mock("mail")
      mail.stubs(:deliver_now).returns(true)
      expectation = MissedNotificationsMailer.expects(:bundle)
      expectation.with { |b, items| block ? block.call(b, items) : true; true } if block
      expectation.returns(mail)
      expectation
    end
end
