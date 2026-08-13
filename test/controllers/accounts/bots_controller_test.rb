require "test_helper"

class Accounts::BotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index" do
    get account_bots_url
    assert_response :ok
    assert_select ".settings-nav__item[aria-current=page]", text: "Bots & webhooks"
  end

  test "show" do
    get account_bot_url(users(:bender))
    assert_response :ok
    assert_select ".settings-nav__item[aria-current=page]", text: "Bots & webhooks"
  end

  test "create" do
    get new_account_bot_url
    assert_response :ok

    post account_bots_url, params: { user: { name: "Bender's Friend" } }
    bot = User.bot.last
    assert_redirected_to account_bot_url(bot)
    assert_equal "Bender's Friend", bot.name
  end

  test "update" do
    get edit_account_bot_url(users(:bender))
    assert_response :ok

    put account_bot_url(users(:bender)), params: { user: { name: "Bender's New Friend" } }
    assert_redirected_to account_bot_url(users(:bender))
    assert_equal "Bender's New Friend", users(:bender).reload.name
  end

  test "destroy" do
    assert_difference -> { User.active_bots.count }, -1 do
      delete account_bot_url(users(:bender))
    end

    assert users(:bender).reload.deactivated?
  end

  test "remove webhook" do
    assert_difference -> { Webhook.count }, -1 do
      put account_bot_url(users(:bender)), params: { user: { name: "Bender's New Friend", webhook_url: "" } }
      assert_redirected_to account_bot_url(users(:bender))
    end
  end

  test "create re-renders the form with a flash alert when the webhook URL is unresolvable" do
    stub_dns_resolution

    assert_no_difference [ -> { User.count }, -> { Webhook.count } ] do
      post account_bots_url, params: { user: { name: "Doomed Bot", webhook_url: "https://nowhere.example.invalid/hook" } }
    end

    assert_response :unprocessable_entity
    assert_match(/could not be resolved/i, flash[:alert])
  end

  test "create re-renders the form with a flash alert when the webhook URL targets a private network" do
    stub_dns_resolution("192.168.1.1")

    assert_no_difference [ -> { User.count }, -> { Webhook.count } ] do
      post account_bots_url, params: { user: { name: "Doomed Bot", webhook_url: "https://internal.example.com/hook" } }
    end

    assert_response :unprocessable_entity
    assert_match(/must not target private or internal networks/i, flash[:alert])
  end

  test "update re-renders the form with a flash alert when the new webhook URL is invalid" do
    stub_dns_resolution("192.168.1.1")

    put account_bot_url(users(:bender)), params: { user: { name: users(:bender).name, webhook_url: "https://internal.example.com/hook" } }

    assert_response :unprocessable_entity
    assert_match(/must not target private or internal networks/i, flash[:alert])
  end
end
