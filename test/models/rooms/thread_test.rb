require "test_helper"

class Rooms::ThreadTest < ActiveSupport::TestCase
  setup do
    @parent_room = rooms(:hq)
    @parent_message = @parent_room.messages.create!(body: "Parent message", creator: users(:david))
  end

  test "find_or_create_for follows both the opener and the parent-message author" do
    thread = Rooms::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert thread.memberships.active.exists?(user_id: users(:david).id)
  end

  test "find_or_create_for skips the author who self-left the parent room" do
    # Self-service leave keeps the row active and only flips involvement to
    # invisible, so an active-row check (viewable_by?) would wrongly still follow.
    @parent_room.memberships.find_by(user: users(:david)).update!(involvement: :invisible)

    thread = Rooms::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert_not thread.memberships.exists?(user_id: users(:david).id)
  end

  test "find_or_create_for skips the author removed from the parent room" do
    @parent_room.memberships.find_by(user: users(:david)).update!(active: false)

    thread = Rooms::Thread.find_or_create_for(@parent_message, creator: users(:jason))

    assert thread.memberships.active.exists?(user_id: users(:jason).id)
    assert_not thread.memberships.exists?(user_id: users(:david).id)
  end

  test "default involvement for thread creator is everything" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "everything", thread.default_involvement(user: users(:david))
  end

  test "default involvement for parent message creator is everything" do
    # Thread created by jason, but parent message by david
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:jason))
    assert_equal "everything", thread.default_involvement(user: users(:david))
  end

  test "default involvement for other users is invisible" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "invisible", thread.default_involvement(user: users(:jz))
  end

  test "default involvement without user is invisible" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "invisible", thread.default_involvement(user: nil)
  end

  test "thread display name includes parent room name" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert_equal "🧵 #{@parent_room.name}", thread.display_name
  end

  test "destroying parent room destroys thread" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread_id = thread.id

    @parent_room.destroy

    assert_not Rooms::Thread.exists?(thread_id)
  end

  test "thread membership granted with mentions involvement by default" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread.involve_user(users(:jz))

    membership = thread.memberships.find_by(user: users(:jz))
    assert membership.present?
    assert membership.receives_mentions?
  end

  test "preload_participant_creators batches ordered participants for multiple threads" do
    thread_one = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread_one.memberships.grant_to([ users(:david), users(:jason), users(:jz) ])
    thread_one.messages.create!(body: "first", creator: users(:david), created_at: 3.minutes.ago)
    thread_one.messages.create!(body: "second", creator: users(:jason), created_at: 2.minutes.ago)

    second_parent = @parent_room.messages.create!(body: "Second parent", creator: users(:jason))
    thread_two = Rooms::Thread.create!(parent_message: second_parent, creator: users(:jason))
    thread_two.memberships.grant_to([ users(:jason), users(:jz) ])
    thread_two.messages.create!(body: "third", creator: users(:jz), created_at: 1.minute.ago)

    participants = Rooms::Thread.preload_participant_creators([ thread_one, thread_two ])

    assert_equal [ users(:david), users(:jason) ], participants.fetch(thread_one.id)
    assert_equal [ users(:jz) ], participants.fetch(thread_two.id)
  end

  test "preload_participant_creators limits per thread and breaks timestamp ties by creator id" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    thread.memberships.grant_to([ users(:david), users(:jason), users(:jz), users(:kevin) ])
    created_at = 1.minute.ago.change(usec: 0)

    thread.messages.create!(body: "one", creator: users(:jz), created_at:)
    thread.messages.create!(body: "two", creator: users(:jason), created_at:)
    thread.messages.create!(body: "three", creator: users(:kevin), created_at:)

    participants = Rooms::Thread.preload_participant_creators([ thread ], limit: 2)

    assert_equal [ users(:jason), users(:kevin) ], participants.fetch(thread.id)
  end

  test "with_thread_participants keeps query count constant as thread count grows" do
    one_thread_parent = @parent_message
    one_thread = Rooms::Thread.create!(parent_message: one_thread_parent, creator: users(:david))
    one_thread.memberships.grant_to([ users(:david), users(:jason) ])
    one_thread.messages.create!(body: "first", creator: users(:david))
    one_thread.messages.create!(body: "second", creator: users(:jason))

    additional_parents = 4.times.map do |i|
      parent = @parent_room.messages.create!(body: "Parent #{i}", creator: users(:david))
      thread = Rooms::Thread.create!(parent_message: parent, creator: users(:david))
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
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
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
  # slug, and Solved behavior now live on Rooms::Post — see rooms/post_test.)
  test "chat threads do not get a slug" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
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
