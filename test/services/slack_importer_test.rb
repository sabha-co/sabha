require "test_helper"
require "zip"

class SlackImporterTest < ActiveSupport::TestCase
  setup do
    @fixtures_path = Rails.root.join("test/fixtures/slack_export")
    @zip_path = Rails.root.join("tmp/test_slack_export.zip")

    # Create ZIP file from fixtures
    create_test_zip
  end

  teardown do
    File.delete(@zip_path) if File.exist?(@zip_path)
  end

  test "imports users from users.json" do
    importer = SlackImporter.new(@zip_path.to_s)

    stats = nil
    assert_difference "User.count", 3 do # 3 active, non-bot users
      stats = importer.import!
    end

    assert_equal 3, stats[:users]

    # Verify user details
    lindy = User.find_by("preferences LIKE ?", "%lindy%")
    assert lindy.present?
    assert_equal "Lindy Smith", lindy.name
    assert_equal "Software Engineer", lindy.bio

    # Check slack metadata stored in preferences (already deserialized by Rails)
    prefs = lindy.preferences
    assert prefs["slack_import"]
    assert_equal "U07Q4MHCP", prefs["slack_user_id"]
    assert_equal "lindy", prefs["slack_username"]
  end

  test "skips deleted and bot users" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    # Verify deleted user not imported
    assert_nil User.find_by("preferences LIKE ?", "%deleted_user%")

    # Verify bot not imported
    assert_nil User.find_by("preferences LIKE ?", "%slackbot%")
  end

  test "imports channels as Rooms::Open" do
    importer = SlackImporter.new(@zip_path.to_s)

    stats = nil
    assert_difference "Rooms::Open.count", 2 do
      stats = importer.import!
    end

    assert_equal 2, stats[:rooms]

    general = Rooms::Open.find_by(slug: "general")
    assert general.present?
    assert_equal "General", general.name

    random = Rooms::Open.find_by(slug: "random")
    assert random.present?
    assert_equal "Random", random.name
  end

  test "assigns channel members from slack export" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    random = Rooms::Open.find_by(slug: "random")

    # Check that imported users are members of their channels
    lindy = User.find_by("preferences LIKE ?", "%lindy%")
    alice = User.find_by("preferences LIKE ?", "%alice%")

    assert general.memberships.exists?(user: lindy)
    assert general.memberships.exists?(user: alice)
    assert random.memberships.exists?(user: lindy)
    assert random.memberships.exists?(user: alice)
  end

  test "imports messages with preserved timestamps" do
    importer = SlackImporter.new(@zip_path.to_s)
    stats = importer.import!

    assert stats[:messages] > 0

    general = Rooms::Open.find_by(slug: "general")
    messages = general.messages.where.not(room_id: Rooms::Thread.pluck(:id)).order(:created_at)

    first_message = messages.first
    assert_equal "Good morning everyone!", first_message.body.to_plain_text

    # Verify timestamp was preserved from Slack export
    expected_time = Time.at(1705312800.000001)
    assert_in_delta expected_time.to_f, first_message.created_at.to_f, 1.0
  end

  test "converts user mentions" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    mention_message = general.messages.find { |m| m.body.to_plain_text.include?("@lindy") }
    assert mention_message.present?
    assert_includes mention_message.body.to_plain_text, "Hey @lindy"
  end

  test "converts channel mentions to @channel" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    channel_message = general.messages.find { |m| m.body.to_plain_text.include?("@channel") }
    assert channel_message.present?
    assert_includes channel_message.body.to_plain_text, "@channel please review"
  end

  test "converts links with display text" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    link_message = general.messages.find { |m| m.body.to_plain_text.include?("Example Site") }
    assert link_message.present?
    assert_includes link_message.body.to_plain_text, "Example Site (https://example.com)"
  end

  test "skips channel_join and channel_leave messages" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    messages = general.messages.map { |m| m.body.to_plain_text }

    assert_not messages.any? { |m| m.include?("has left the channel") }
    assert_not messages.any? { |m| m.include?("has joined the channel") }
  end

  test "skips channel_purpose messages" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    general = Rooms::Open.find_by(slug: "general")
    messages = general.messages.map { |m| m.body.to_plain_text }

    assert_not messages.any? { |m| m.include?("set the channel purpose") }
  end

  test "imports reactions as boosts" do
    importer = SlackImporter.new(@zip_path.to_s)
    stats = importer.import!

    assert_equal 3, stats[:boosts] # 2 thumbsup + 1 heart

    message_with_reactions = Message.find_by("client_message_id LIKE ?", "%1705312980%")
    assert message_with_reactions.present?
    assert_equal 3, message_with_reactions.boosts.count
  end

  test "converts emoji names to unicode" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    message_with_reactions = Message.find_by("client_message_id LIKE ?", "%1705312980%")
    emojis = message_with_reactions.boosts.pluck(:content)

    assert_includes emojis, Slack::EmojiConverter::MAPPING["thumbsup"]
    assert_includes emojis, Slack::EmojiConverter::MAPPING["heart"]
  end

  test "creates threads from thread_ts" do
    importer = SlackImporter.new(@zip_path.to_s)
    stats = importer.import!

    assert_equal 1, stats[:threads]

    # Find the thread parent
    parent_message = Message.find_by("client_message_id LIKE ?", "%1705313200%")
    assert parent_message.present?

    # Verify thread was created
    thread_room = parent_message.threads.first
    assert thread_room.present?
    assert_kind_of Rooms::Thread, thread_room

    # Verify reply messages moved to thread
    assert_equal 2, thread_room.messages.count
  end

  test "handles channel references in messages" do
    importer = SlackImporter.new(@zip_path.to_s)
    importer.import!

    random = Rooms::Open.find_by(slug: "random")
    channel_ref_message = random.messages.find { |m| m.body.to_plain_text.include?("#general") }
    assert channel_ref_message.present?
  end

  test "is idempotent - re-importing same data does not create duplicates" do
    # First import
    importer1 = SlackImporter.new(@zip_path.to_s)
    stats1 = importer1.import!

    room_count_after_first = Room.count
    user_count_after_first = User.count
    message_count_after_first = Message.count

    assert Rooms::Open.exists?(slug: "general")
    assert stats1[:rooms] > 0
    assert stats1[:users] > 0

    # Second import should skip existing records
    importer2 = SlackImporter.new(@zip_path.to_s)
    stats2 = importer2.import!

    assert_equal room_count_after_first, Room.count, "Room count should not change on re-import"
    assert_equal user_count_after_first, User.count, "User count should not change on re-import"
    assert_equal message_count_after_first, Message.count, "Message count should not change on re-import"
    assert_equal 0, stats2[:rooms], "Stats should show 0 new rooms"
    assert_equal 0, stats2[:users], "Stats should show 0 new users"
  end

  test "returns stats after import" do
    importer = SlackImporter.new(@zip_path.to_s)
    stats = importer.import!

    assert stats[:users] > 0
    assert stats[:rooms] > 0
    assert stats[:messages] > 0
    assert stats.key?(:boosts)
    assert stats.key?(:threads)
  end

  test "rolls back on error" do
    # Force an error during messages import
    Slack::MessagesImporter.any_instance.stubs(:import).raises(StandardError.new("Test error"))

    importer = SlackImporter.new(@zip_path.to_s)

    assert_no_difference [ "User.count", "Room.count", "Message.count" ] do
      assert_raises(StandardError) do
        importer.import!
      end
    end
  end

  test "handles missing optional files gracefully" do
    # Create minimal ZIP without groups.json and dms.json
    create_minimal_test_zip

    importer = SlackImporter.new(@zip_path.to_s)

    assert_nothing_raised do
      importer.import!
    end
  end

  test "validate returns valid result for valid export" do
    result = SlackImporter.validate(@zip_path.to_s)

    assert result.valid?
    assert_empty result.errors
    assert_equal 3, result.stats[:users_count]
    assert_equal 2, result.stats[:channels_count]
    assert result.stats[:message_files_count] > 0
  end

  test "validate returns error for missing users.json" do
    create_zip_without("users.json")

    result = SlackImporter.validate(@zip_path.to_s)

    assert_not result.valid?
    assert result.errors.any? { |e| e.include?("users.json") }
  end

  test "validate returns error for missing channels.json" do
    create_zip_without("channels.json")

    result = SlackImporter.validate(@zip_path.to_s)

    assert_not result.valid?
    assert result.errors.any? { |e| e.include?("channels.json") }
  end

  test "validate returns error for non-existent file" do
    result = SlackImporter.validate("/nonexistent/path.zip")

    assert_not result.valid?
    assert result.errors.any? { |e| e.include?("File not found") }
  end

  test "validate returns warning for public-only export" do
    create_minimal_test_zip

    result = SlackImporter.validate(@zip_path.to_s)

    assert result.valid?
    assert result.warnings.any? { |w| w.include?("public channels") }
  end

  private

  def create_test_zip
    File.delete(@zip_path) if File.exist?(@zip_path)

    Zip::File.open(@zip_path, create: true) do |zipfile|
      # Add top-level JSON files
      [ "users.json", "channels.json" ].each do |filename|
        file_path = @fixtures_path.join(filename)
        zipfile.add(filename, file_path) if File.exist?(file_path)
      end

      # Add channel message folders
      Dir.glob(@fixtures_path.join("*/")).each do |dir|
        folder_name = File.basename(dir)
        next if folder_name.start_with?(".")

        Dir.glob(File.join(dir, "*.json")).each do |json_file|
          entry_name = "#{folder_name}/#{File.basename(json_file)}"
          zipfile.add(entry_name, json_file)
        end
      end
    end
  end

  def create_minimal_test_zip
    File.delete(@zip_path) if File.exist?(@zip_path)

    Zip::File.open(@zip_path, create: true) do |zipfile|
      zipfile.add("users.json", @fixtures_path.join("users.json"))
      zipfile.add("channels.json", @fixtures_path.join("channels.json"))
    end
  end

  def create_zip_without(exclude_file)
    File.delete(@zip_path) if File.exist?(@zip_path)

    Zip::File.open(@zip_path, create: true) do |zipfile|
      [ "users.json", "channels.json" ].each do |filename|
        next if filename == exclude_file
        file_path = @fixtures_path.join(filename)
        zipfile.add(filename, file_path) if File.exist?(file_path)
      end
    end
  end
end
