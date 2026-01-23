require "test_helper"

class Rooms::ThreadTest < ActiveSupport::TestCase
  setup do
    @parent_room = rooms(:hq)
    @parent_message = @parent_room.messages.create!(body: "Parent message", creator: users(:david))
  end

  test "thread requires parent message" do
    thread = Rooms::Thread.new(creator: users(:david))
    assert_not thread.valid?
    assert thread.errors[:parent_message].present?
  end

  test "thread with parent message is valid" do
    thread = Rooms::Thread.new(parent_message: @parent_message, creator: users(:david))
    assert thread.valid?
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

  test "thread is identified as thread type" do
    thread = Rooms::Thread.create!(parent_message: @parent_message, creator: users(:david))
    assert thread.thread?
    assert_not thread.direct?
    assert_not thread.open?
    assert_not thread.closed?
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
end
