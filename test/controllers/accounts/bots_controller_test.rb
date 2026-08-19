require "test_helper"

class Accounts::BotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index lists bots" do
    get account_bots_url
    assert_response :ok
    assert_select ".settings-nav__item[aria-current=page]", text: "Bots & webhooks"
    assert_select ".bot-row__hook", text: users(:bender).webhook_url
  end

  test "new renders the editor frame" do
    get new_account_bot_url
    assert_response :ok
    assert_select "turbo-frame#bot_editor .scrim-dialog__title", text: "New bot"
  end

  test "edit renders the prefilled editor frame" do
    get edit_account_bot_url(users(:bender))
    assert_response :ok
    assert_select "turbo-frame#bot_editor .scrim-dialog__title", text: "Edit bot"
  end

  test "create mints a bot and streams the one-time key" do
    assert_difference -> { User.active_bots.count }, 1 do
      post account_bots_url, params: { user: { name: "Bender's Friend" } }, as: :turbo_stream
    end
    assert_response :success

    bot = User.active_bots.order(:created_at).last
    assert_equal "Bender's Friend", bot.name
    assert_match(/sabha_bot_/, @response.body)
  end

  test "create rejects a blank name" do
    assert_no_difference -> { User.active_bots.count } do
      post account_bots_url, params: { user: { name: "  " } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_select ".field-error"
  end

  test "create rejects a duplicate name" do
    assert_no_difference -> { User.active_bots.count } do
      post account_bots_url, params: { user: { name: users(:bender).name } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_select ".field-error", text: "A bot already uses that name."
  end

  test "create syncs the selected rooms" do
    room = Room.active.without_directs.without_threads.first
    post account_bots_url, params: { user: { name: "Room Bot", room_ids: [ room.id ] } }, as: :turbo_stream

    bot = User.active_bots.find_by(name: "Room Bot")
    assert_includes bot.room_memberships.map(&:room), room
  end

  test "update edits the bot and streams the row" do
    put account_bot_url(users(:bender)), params: { user: { name: "Bender's New Friend" } }, as: :turbo_stream
    assert_response :success
    assert_equal "Bender's New Friend", users(:bender).reload.name
  end

  test "destroy deactivates the bot" do
    assert_difference -> { User.active_bots.count }, -1 do
      delete account_bot_url(users(:bender)), as: :turbo_stream
    end
    assert_response :success
    assert users(:bender).reload.deactivated?
  end

  test "remove webhook" do
    assert_difference -> { Webhook.count }, -1 do
      put account_bot_url(users(:bender)), params: { user: { name: users(:bender).name, webhook_url: "" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "create surfaces an unresolvable webhook URL as a field error" do
    stub_dns_resolution

    assert_no_difference [ -> { User.count }, -> { Webhook.count } ] do
      post account_bots_url, params: { user: { name: "Doomed Bot", webhook_url: "https://nowhere.example.invalid/hook" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select ".field-error", text: /could not be resolved/i
  end

  test "create surfaces a private-network webhook URL as a field error" do
    stub_dns_resolution("192.168.1.1")

    assert_no_difference [ -> { User.count }, -> { Webhook.count } ] do
      post account_bots_url, params: { user: { name: "Doomed Bot", webhook_url: "https://internal.example.com/hook" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select ".field-error", text: /must not target private or internal networks/i
  end

  test "update surfaces an invalid webhook URL as a field error" do
    stub_dns_resolution("192.168.1.1")

    put account_bot_url(users(:bender)), params: { user: { name: users(:bender).name, webhook_url: "https://internal.example.com/hook" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select ".field-error", text: /must not target private or internal networks/i
  end
end
