require "test_helper"

class Messages::BoostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @message = messages(:first)
  end

  test "create" do
    assert_turbo_stream_broadcasts [ @message.room, :messages ], count: 1 do
      assert_difference -> { @message.boosts.count }, 1 do
        post message_boosts_url(@message, format: :turbo_stream), params: { boost: { content: "Morning!" } }
        assert_response :success
      end
    end
  end

  test "destroy" do
    assert_turbo_stream_broadcasts [ @message.room, :messages ], count: 1 do
      assert_difference -> { @message.boosts.count }, -1 do
        delete message_boost_url(@message, boosts(:first), format: :turbo_stream)
        assert_response :success
      end
    end
  end

  test "duplicate boost with same content is silently ignored" do
    @message.boosts.create!(content: "Hello!", booster: users(:david))

    assert_no_difference -> { @message.boosts.count } do
      post message_boosts_url(@message, format: :turbo_stream), params: { boost: { content: "Hello!" } }
      assert_response :success
    end
  end

  test "destroying a boost clears the notification it created" do
    # The notifications -> boosts FK has no ON DELETE CASCADE, so a boost must
    # clear its notification itself or the destroy blows up with a foreign-key
    # violation (a 500 the client saw as "Content missing").
    boost = @message.boosts.create!(content: "🎉", booster: users(:david))
    Notification.create!(user: users(:kevin), actor: users(:david),
                         message: @message, activity_type: "boost", boost_id: boost.id)

    assert_difference -> { Notification.where(boost_id: boost.id).count }, -1 do
      assert_difference -> { @message.boosts.count }, -1 do
        delete message_boost_url(@message, boost, format: :turbo_stream)
        assert_response :success
      end
    end
  end

  test "a forum member without a post membership can boost a message in a post" do
    forum = Rooms::Forum.create_for({ name: "Help", creator: users(:david) }, users: [ users(:david), users(:kevin) ])
    forum_post = Current.set(user: users(:david)) { forum.post!(title: "Q", body: "<div>b</div>") }
    message = forum_post.messages.first

    sign_in :kevin
    assert_not Membership.exists?(room_id: forum_post.id, user_id: users(:kevin).id), "kevin is a forum member, not a post follower"

    assert_difference -> { message.boosts.count }, 1 do
      post message_boosts_url(message, format: :turbo_stream), params: { boost: { content: "Nice" } }
      assert_response :success
    end
  end
end
