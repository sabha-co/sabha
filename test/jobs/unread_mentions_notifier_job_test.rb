require "test_helper"

class UnreadMentionsNotifierJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @david = users(:david)
    @room = rooms(:designers)
    @room.update_column(:created_at, 1.week.ago)
    Membership.update_all(notified_until: nil)
  end

  test "sends email to subscribed users with unread mentions older than 12 hours" do
    @david.subscribe_to_emails
    create_mention_for(@david, created_at: 13.hours.ago)

    assert_emails 1 do
      UnreadMentionsNotifierJob.new.perform
    end
  end

  test "skips unsubscribed users even with unread mentions" do
    @david.unsubscribe_from_emails
    create_mention_for(@david, created_at: 13.hours.ago)

    assert_no_emails do
      UnreadMentionsNotifierJob.new.perform
    end
  end

  test "skips mentions newer than 12 hours" do
    @david.subscribe_to_emails
    create_mention_for(@david, created_at: 6.hours.ago)

    assert_no_emails do
      UnreadMentionsNotifierJob.new.perform
    end
  end

  private

  def create_mention_for(user, created_at:)
    membership = Membership.find_by(user: user, room: @room)
    membership.update!(involvement: :everything, unread_at: created_at - 1.hour, notified_until: nil)

    message = Message.create!(
      room: @room,
      creator: users(:jz),
      body: "Hey @#{user.name}!",
      created_at: created_at
    )
    Mention.create!(user: user, message: message)
  end
end
