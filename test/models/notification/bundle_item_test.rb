require "test_helper"

class Notification::BundleItemTest < ActiveSupport::TestCase
  setup do
    @user    = users(:jason)
    @actor   = users(:david)
    @room    = rooms(:designers)
    @message = @room.messages.create!(body: "hi", creator: @actor, client_message_id: "bundle_item_#{SecureRandom.hex(4)}")
    @bundle  = Notification::Bundle.create!(
      user: @user, frequency: :hourly,
      starts_at: Time.current, ends_at: 1.hour.from_now
    )
  end

  test "kind must be one of mention or direct_message" do
    item = Notification::BundleItem.new(bundle: @bundle, message: @message, actor: @actor, kind: "thread_reply")
    refute item.valid?
    assert_includes item.errors[:kind], "is not included in the list"
  end

  test "unique on (bundle_id, message_id, kind)" do
    Notification::BundleItem.create!(bundle: @bundle, message: @message, actor: @actor, kind: "mention")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Notification::BundleItem.create!(bundle: @bundle, message: @message, actor: @actor, kind: "mention")
    end
  end

  test "same message can have both mention and direct_message kinds in the same bundle" do
    Notification::BundleItem.create!(bundle: @bundle, message: @message, actor: @actor, kind: "mention")

    assert_nothing_raised do
      Notification::BundleItem.create!(bundle: @bundle, message: @message, actor: @actor, kind: "direct_message")
    end
  end
end
