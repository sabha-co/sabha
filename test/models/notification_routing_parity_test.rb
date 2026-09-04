require "test_helper"

class NotificationRoutingParityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "desktop routing vocabulary matches web push" do
    assert_equal Notification::Routing::PUSH_TYPES, Notification::Routing::DESKTOP_TYPES
  end

  Notification::Routing::PUSH_TYPES.each do |activity_type|
    test "desktop recipients match push recipients for #{activity_type}" do
      message = sample_message_for(activity_type)

      assert_equal message.push_recipient_user_ids_for(activity_type),
                   message.desktop_recipient_user_ids_for(activity_type)
    end
  end

  private
    def sample_message_for(activity_type)
      case activity_type
      when :mention
        rooms(:designers).messages.create!(
          body: "Hey #{mention_attachment_for(:kevin)}",
          creator: users(:david),
          client_message_id: "routing_parity_mention"
        )
      when :direct_message
        rooms(:david_and_jason).messages.create!(
          body: "Routing parity DM",
          creator: users(:david),
          client_message_id: "routing_parity_dm"
        )
      when :everyone_room_message
        everyone_sgid = Everyone.new.attachable_sgid
        body = %(<div>Heads up <action-text-attachment sgid="#{everyone_sgid}" content-type="application/vnd.sabha.mention"></action-text-attachment></div>)
        rooms(:hq).messages.create!(
          body: body,
          creator: users(:david),
          client_message_id: "routing_parity_everyone"
        )
      when :thread_reply
        parent = rooms(:designers).messages.create!(
          body: "Thread parent",
          creator: users(:david),
          client_message_id: "routing_parity_thread_parent"
        )
        thread = parent.threads.create!(creator: users(:david))
        thread.messages.create!(
          body: "Thread reply",
          creator: users(:david),
          client_message_id: "routing_parity_thread_reply"
        )
      end
    end
end
