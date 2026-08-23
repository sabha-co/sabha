require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include ForumTestHelper

  # _url helpers need a host; supply one locally so we never mutate the global
  # routes.default_url_options (a nil there leaks into other suites' url helpers).
  def default_url_options
    { host: "example.com" }
  end

  test "a forum post's opening message permalinks to the gallery deep-link, no reply anchor" do
    post = create_forum_post(title: "How do I export?")

    assert_equal room_path(post.parent_room, post: post.slug), message_permalink_path(post.messages.first)
  end

  test "a forum reply permalinks to the gallery deep-link anchored to the reply" do
    post = create_forum_post
    reply = Current.set(user: users(:david)) { post.messages.create!(body: "<div>a reply</div>") }

    assert_equal room_path(post.parent_room, post: post.slug, message_id: reply.id), message_permalink_path(reply)
  end

  test "a chat message still permalinks to its room anchor" do
    message = messages(:first)

    assert_equal room_at_message_path(message.room, message), message_permalink_path(message)
  end

  test "a message inside a chat thread permalinks to the parent message's anchor" do
    parent = messages(:first)
    thread = Rooms::Thread.find_or_create_for(parent, creator: users(:david))
    reply = Current.set(user: users(:david)) { thread.messages.create!(body: "<div>a thread reply</div>") }

    assert_equal room_at_message_path(parent.room, parent), message_permalink_path(reply)
    assert_equal room_at_message_url(parent.room, parent), message_permalink_url(reply)
  end

  test "a forum post's opening message url-permalinks to the gallery deep-link, no reply anchor" do
    post = create_forum_post(title: "How do I export?")

    assert_equal room_url(post.parent_room, post: post.slug), message_permalink_url(post.messages.first)
  end

  test "a forum reply url-permalinks to the gallery deep-link anchored to the reply" do
    post = create_forum_post
    reply = Current.set(user: users(:david)) { post.messages.create!(body: "<div>a reply</div>") }

    assert_equal room_url(post.parent_room, post: post.slug, message_id: reply.id), message_permalink_url(reply)
  end

  test "a chat message still url-permalinks to its room anchor" do
    message = messages(:first)

    assert_equal room_at_message_url(message.room, message), message_permalink_url(message)
  end
end
