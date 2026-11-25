require "test_helper"

class Channels::ThreadTest < ActiveSupport::TestCase
  setup do
    @parent_channel = channels(:hq)
    @parent_message = @parent_channel.messages.create!(body: "Parent message", creator: users(:david))
  end

  test "find_or_create_for follows both the opener and the parent-message author" do
    thread = Channels::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert thread.memberships.active.exists?(user_id: users(:david).id)
  end

  test "find_or_create_for skips the author who self-left the parent channel" do
    # Self-service leave keeps the row active and only flips involvement to
    # invisible, so an active-row check (viewable_by?) would wrongly still follow.
    @parent_channel.memberships.find_by(user: users(:david)).update!(involvement: :invisible)

    thread = Channels::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert_not thread.memberships.exists?(user_id: users(:david).id)
  end

  test "find_or_create_for skips the author removed from the parent channel" do
    @parent_channel.memberships.find_by(user: users(:david)).update!(active: false)

    thread = Channels::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert_not thread.memberships.exists?(user_id: users(:david).id)
  end

  test "reply_to materializes the thread lazily with its first reply" do
    message = nil
    assert_difference -> { Channels::Thread.count }, 1 do
      message = Channels::Thread.reply_to(@parent_message, creator: users(:jason), message_params: { body: "First reply" })
    end

    assert_equal "First reply", message.plain_text_body
    assert_equal @parent_message.id, message.channel.parent_message_id
    assert message.channel.memberships.active.exists?(user_id: users(:jason).id), "the replier follows the thread they opened"
  end

  test "reply_to is idempotent — a second reply reuses the existing thread" do
    first = Channels::Thread.reply_to(@parent_message, creator: users(:jason), message_params: { body: "one" })

    assert_no_difference -> { Channels::Thread.count } do
      second = Channels::Thread.reply_to(@parent_message, creator: users(:david), message_params: { body: "two" })
      assert_equal first.channel_id, second.channel_id
    end
  end

  test "reply_to rejects a blank reply and materializes nothing" do
    assert_no_difference [ -> { Channels::Thread.count }, -> { Message.count } ] do
      assert_raises Channels::Thread::BlankReplyError do
        Channels::Thread.reply_to(@parent_message, creator: users(:jason), message_params: { body: "  " })
      end
    end
  end

  test "materializing a thread supersedes open provisional panels for the parent message" do
    assert_turbo_stream_broadcasts [ @parent_message, :thread ], count: 1 do
      Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    end
  end

  # A thread membership row is a follow, never access — viewable_by? delegates to
  # the parent channel and never consults the thread's own memberships. Build a fresh
  # parent so we control who is a member (the setup's channels(:hq) has every user).
  test "a thread follow row grants no access — access derives from the parent channel" do
    parent = Channels::Closed.create!(name: "Fresh channel", creator: users(:david))
    parent.memberships.grant_to(users(:jason))
    parent_message = parent.messages.create!(body: "topic", creator: users(:david))
    thread = Channels::Thread.find_or_create_for(parent_message, creator: users(:david))

    outsider = users(:kevin) # not a member of `parent`
    Membership.create!(channel: thread, user: outsider, involvement: "everything")

    assert_not thread.viewable_by?(outsider), "a follow row on the thread does not confer access"
    assert thread.viewable_by?(users(:jason)), "a parent member views the thread via derived access"
    assert_not thread.viewable_by?(nil)
  end

  test "default involvement for thread creator is everything" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "everything", thread.default_involvement(user: users(:david))
  end

  test "default involvement for parent message creator is everything" do
    # Thread created by jason, but parent message by david
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:jason))
    assert_equal "everything", thread.default_involvement(user: users(:david))
  end

  test "default involvement for other users is invisible" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "invisible", thread.default_involvement(user: users(:jz))
  end

  test "default involvement without user is invisible" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "invisible", thread.default_involvement(user: nil)
  end

  test "thread display name includes parent channel name" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "🧵 #{@parent_channel.name}", thread.display_name
  end

  test "destroying parent channel destroys thread" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread_id = thread.id

    @parent_channel.destroy

    assert_not Channels::Thread.exists?(thread_id)
  end

  test "thread membership granted with mentions involvement by default" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread.involve_user(users(:jz))

    membership = thread.memberships.find_by(user: users(:jz))
    assert membership.present?
    assert membership.receives_mentions?
  end

  test "preload_participant_creators batches ordered participants for multiple threads" do
    thread_one = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread_one.memberships.grant_to([ users(:david), users(:jason), users(:jz) ])
    thread_one.messages.create!(body: "first", creator: users(:david), created_at: 3.minutes.ago)
    thread_one.messages.create!(body: "second", creator: users(:jason), created_at: 2.minutes.ago)

    second_parent = @parent_channel.messages.create!(body: "Second parent", creator: users(:jason))
    thread_two = Channels::Thread.create!(parent_message: second_parent, creator: users(:jason))
    thread_two.memberships.grant_to([ users(:jason), users(:jz) ])
    thread_two.messages.create!(body: "third", creator: users(:jz), created_at: 1.minute.ago)

    participants = Channels::Thread.preload_participant_creators([ thread_one, thread_two ])

    assert_equal [ users(:david), users(:jason) ], participants.fetch(thread_one.id)
    assert_equal [ users(:jz) ], participants.fetch(thread_two.id)
  end

  test "preload_participant_creators limits per thread and breaks timestamp ties by creator id" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason), users(:jz), users(:kevin) ])
    created_at = 1.minute.ago.change(usec: 0)

    thread.messages.create!(body: "one", creator: users(:jz), created_at:)
    thread.messages.create!(body: "two", creator: users(:jason), created_at:)
    thread.messages.create!(body: "three", creator: users(:kevin), created_at:)

    participants = Channels::Thread.preload_participant_creators([ thread ], limit: 2)

    assert_equal [ users(:jason), users(:kevin) ], participants.fetch(thread.id)
  end

  test "with_thread_participants keeps query count constant as thread count grows" do
    one_thread_parent = @parent_message
    one_thread = Channels::Thread.create!(parent_message: one_thread_parent, creator: users(:david))
    one_thread.memberships.grant_to([ users(:david), users(:jason) ])
    one_thread.messages.create!(body: "first", creator: users(:david))
    one_thread.messages.create!(body: "second", creator: users(:jason))

    additional_parents = 4.times.map do |i|
      parent = @parent_channel.messages.create!(body: "Parent #{i}", creator: users(:david))
      thread = Channels::Thread.create!(parent_message: parent, creator: users(:david))
      thread.memberships.grant_to([ users(:david), users(:jason) ])
      thread.messages.create!(body: "reply #{i}", creator: users(:jason))
      parent
    end

    one_loaded_message = Message.where(id: one_thread_parent.id).includes(:threads).to_a
    five_loaded_messages = Message.where(id: [ one_thread_parent.id, *additional_parents.map(&:id) ]).includes(:threads).to_a

    one_thread_queries = count_application_queries {
      Message.with_thread_participants(one_loaded_message)
    }

    five_thread_queries = count_application_queries {
      Message.with_thread_participants(five_loaded_messages)
    }

    assert_equal one_thread_queries, five_thread_queries
  end

  test "threads partial falls back to participant_creators when message is unstamped" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason) ])
    thread.messages.create!(body: "reply", creator: users(:jason), client_message_id: "fallback_reply")

    unstamped_message = Message.where(id: @parent_message.id).includes(:threads).first
    assert_nil unstamped_message.thread_participants_for(thread)

    html = Current.set(user: users(:david)) do
      ApplicationController.render(partial: "messages/threads", locals: { message: unstamped_message })
    end

    assert_includes html, users(:jason).name
  end

  # Chat threads are nameless and never get a forum-post slug. (Forum-post title,
  # slug, and Solved behavior now live on Channels::Post — see channels/post_test.)
  test "chat threads do not get a slug" do
    thread = Channels::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_nil thread.slug
  end

  private
    def count_application_queries(&block)
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql]
        name = payload[:name]
        next if payload[:cached]
        next if name == "SCHEMA"
        next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

        @query_count += 1
      end

      @query_count = 0
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { block.call }
      end
      @query_count
    end
end
