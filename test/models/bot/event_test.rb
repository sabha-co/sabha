require "test_helper"

class Bot::EventTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @room = rooms(:watercooler)
    @bot = users(:bender)
    @message = @room.messages.create!(creator: users(:david),
      body: "<div>Hello #{mention_attachment_for(:bender)}</div>")
    @base_url = "https://chat.example.test/workspace"
    @stream = BotEventsChannel.stream_name_for(@bot)
  end

  test "dispatch without a request delivers both transports and captures the webhook before enqueue" do
    job = assert_enqueued_with(job: Bot::WebhookJob) do
      assert_broadcasts @stream, 1 do
        Bot::Event.new(@message, :created, base_url: @base_url).dispatch
      end
    end

    webhook, event, raw_payload, room, reply = job.arguments
    payload = JSON.parse(raw_payload)
    assert_equal @bot.webhook, webhook
    assert_equal "message_created", event
    assert_equal @room, room
    assert_equal true, reply
    assert_equal payload, JSON.parse(broadcasts(@stream).last)
    assert_equal @base_url + Rails.application.routes.url_helpers.room_at_message_path(@room, @message), payload.dig("message", "url")
    assert_equal @base_url + Rails.application.routes.url_helpers.user_path(users(:david)), payload.dig("user", "url")

    @message.update!(body: "Edited after dispatch")
    assert_not_equal @message.plain_text_body, payload.dig("message", "body", "plain")
    assert_equal "Hello @Bender Bot", payload.dig("message", "body", "plain")
  end

  test "bots without webhooks still receive their payload" do
    @bot.webhook.destroy!

    assert_no_enqueued_jobs only: Bot::WebhookJob do
      assert_broadcasts @stream, 1 do
        Bot::Event.new(@message, :created, base_url: @base_url).dispatch
      end
    end
    assert_equal "message_created", JSON.parse(broadcasts(@stream).last)["event"]
  end

  test "everything recipients receive sub-room creates without a mention and retain reply permission" do
    thread = Rooms::Thread.find_or_create_for(messages(:fourth), creator: users(:david))
    thread.memberships.create!(user: @bot, involvement: :everything)
    message = thread.messages.create!(creator: users(:david), body: "A thread follow-up")

    job = assert_enqueued_with(job: Bot::WebhookJob) do
      Bot::Event.new(message, :created, base_url: @base_url).dispatch
    end

    assert_equal true, job.arguments.last
    assert_equal({ "id" => thread.id, "parent_message_id" => messages(:fourth).id },
      JSON.parse(job.arguments[2]).dig("message", "thread"))
  end

  test "bot-authored direct messages do not require mentions" do
    room = Rooms::Direct.create_for({ creator: users(:david) }, users: [ users(:david), @bot ])
    message = room.messages.create!(creator: @bot, body: "Bot-authored direct message")

    assert_broadcasts @stream, 1 do
      Bot::Event.new(message, :created, base_url: @base_url).dispatch
    end
    assert_equal @bot.id, JSON.parse(broadcasts(@stream).last).dig("user", "id")
  end

  test "updates deliver to existing members without granting webhook reply permission" do
    assert_enqueued_jobs 2, only: Bot::WebhookJob do
      Bot::Event.new(@message, :updated, base_url: @base_url).dispatch
    end
    jobs = enqueued_jobs.select { |job| job[:job] == Bot::WebhookJob }.map do |job|
      ActiveJob::Arguments.deserialize(job[:args])
    end
    assert_equal [ users(:bender).webhook.id, users(:nsa).webhook.id ].sort, jobs.map { |args| args.first.id }.sort
    assert jobs.all? { |args| args[1] == "message_updated" && args.last == false }
  end

  test "account events reach active bots without room memberships" do
    users(:nsa).update_column(:status, :deactivated)
    betty = users(:betty)
    assert_not betty.memberships.exists?

    assert_no_broadcasts BotEventsChannel.stream_name_for(users(:nsa)) do
      assert_broadcasts BotEventsChannel.stream_name_for(betty), 1 do
        assert_enqueued_jobs 2, only: Bot::WebhookJob do
          Bot::Event.new(users(:kevin), :deleted, base_url: @base_url).dispatch
        end
      end
    end
    payload = JSON.parse(broadcasts(BotEventsChannel.stream_name_for(betty)).last)
    assert_equal "user_deleted", payload["event"]
    assert_equal users(:kevin).id, payload.dig("user", "id")
    assert_not payload.key?("room")
  end

  test "destroyed reactions retain their payload and current nil webhook reply room" do
    boost = @message.boosts.create!(booster: users(:david), content: "Nice")
    boost.destroy!

    job = assert_enqueued_with(job: Bot::WebhookJob) do
      Bot::Event.new(boost, :deleted, base_url: @base_url).dispatch
    end
    assert_equal "boost_deleted", job.arguments[1]
    assert_equal({ "id" => boost.id, "body" => "Nice" }, JSON.parse(job.arguments[2])["boost"])
    assert_nil job.arguments[3]
    assert_equal false, job.arguments.last
  end

  test "broadcast errors propagate before any webhook is queued" do
    ActionCable.server.expects(:broadcast).with(@stream, anything).raises(IOError, "broadcast unavailable")

    assert_no_enqueued_jobs only: Bot::WebhookJob do
      assert_raises(IOError) { Bot::Event.new(@message, :created, base_url: @base_url).dispatch }
    end
  end

  test "enqueue errors propagate after the WebSocket broadcast" do
    Bot::WebhookJob.expects(:perform_later).raises(IOError, "queue unavailable")

    assert_broadcasts @stream, 1 do
      assert_raises(IOError) { Bot::Event.new(@message, :created, base_url: @base_url).dispatch }
    end
  end
end
