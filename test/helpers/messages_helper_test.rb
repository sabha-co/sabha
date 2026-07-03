require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include ForumTestHelper

  test "a forum post's opening message permalinks to its /f/:slug page, not the gallery" do
    post = create_forum_post(title: "How do I export?")

    assert_equal forum_post_path(post.slug), message_permalink_path(post.parent_message)
  end

  test "a forum reply permalinks to the post page anchored to the reply" do
    post = create_forum_post
    reply = Current.set(user: users(:david)) { post.messages.create!(body: "<div>a reply</div>") }

    assert_equal forum_post_path(post.slug, message_id: reply.id), message_permalink_path(reply)
  end

  test "a chat message still permalinks to its room anchor" do
    message = messages(:first)

    assert_equal room_at_message_path(message.room, message), message_permalink_path(message)
  end
end
