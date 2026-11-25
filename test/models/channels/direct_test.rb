require "test_helper"

class Channels::DirectTest < ActiveSupport::TestCase
  test "create channel for same users" do
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    assert channel.users.include?(users(:david))
    assert channel.users.include?(users(:kevin))
    assert_not channel.users.include?(users(:jason))
  end

  test "only one channel will exist for the same users" do
    channel1 = Channels::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    channel2 = Channels::Direct.find_or_create_for([ users(:kevin), users(:david) ])
    assert_equal channel1, channel2
  end

  test "default involvement for new users" do
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:kevin) ])
    assert channel.memberships.all? { |m| m.involved_in_everything? }
  end

  # Lazy materialization — a DM exists only once someone sends something.

  test "message_to materializes the DM lazily with its first message" do
    jz, rachel = users(:jz), users(:rachel)
    Current.user = jz

    message = nil
    assert_difference -> { Channels::Direct.count }, 1 do
      message = Channels::Direct.message_to([ jz, rachel ], creator: jz, message_params: { body: "First message" })
    end

    assert_equal "First message", message.plain_text_body
    assert message.channel.users.include?(jz)
    assert message.channel.users.include?(rachel)
  end

  test "message_to is idempotent — a second message reuses the existing DM" do
    jz, rachel = users(:jz), users(:rachel)
    Current.user = jz

    first = Channels::Direct.message_to([ jz, rachel ], creator: jz, message_params: { body: "one" })

    assert_no_difference -> { Channels::Direct.count } do
      second = Channels::Direct.message_to([ rachel, jz ], creator: rachel, message_params: { body: "two" })
      assert_equal first.channel_id, second.channel_id
    end
  end

  test "message_to rejects a blank message and materializes nothing" do
    jz, rachel = users(:jz), users(:rachel)
    Current.user = jz

    assert_no_difference [ -> { Channels::Direct.count }, -> { Message.count } ] do
      assert_raises Channels::Direct::BlankMessageError do
        Channels::Direct.message_to([ jz, rachel ], creator: jz, message_params: { body: "  " })
      end
    end
  end

  test "for finds an existing DM without creating one" do
    jz, rachel = users(:jz), users(:rachel)
    Current.user = jz

    assert_nil Channels::Direct.for([ jz, rachel ])

    existing = Channels::Direct.find_or_create_for([ jz, rachel ])

    assert_no_difference -> { Channels::Direct.count } do
      assert_equal existing, Channels::Direct.for([ jz, rachel ])
    end
  end

  test "broadcasts to sidebar for each member on creation" do
    jz = users(:jz)
    rachel = users(:rachel)
    Current.user = jz

    jz_stream = "#{jz.to_gid_param}:channels"
    rachel_stream = "#{rachel.to_gid_param}:channels"

    assert_broadcasts jz_stream, 1 do
      assert_broadcasts rachel_stream, 1 do
        Channels::Direct.find_or_create_for([ jz, rachel ])
      end
    end
  end

  test "one_on_one? returns true for two-person DM" do
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:jason) ])
    assert channel.one_on_one?
  end

  test "one_on_one? returns false for group DM" do
    Current.user = users(:david)
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:jason), users(:kevin) ])
    assert_not channel.one_on_one?
  end

  test "other_user returns the other participant in one-on-one DM" do
    Current.user = users(:david)
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:jason) ])

    assert_equal users(:jason), channel.other_user
  end

  test "other_user returns nil for group DM" do
    Current.user = users(:david)
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:jason), users(:kevin) ])

    assert_nil channel.other_user
  end

  test "other_user accepts for_user parameter" do
    channel = Channels::Direct.find_or_create_for([ users(:david), users(:jason) ])

    assert_equal users(:jason), channel.other_user(for_user: users(:david))
    assert_equal users(:david), channel.other_user(for_user: users(:jason))
  end
end
