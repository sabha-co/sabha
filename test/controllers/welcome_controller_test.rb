require "test_helper"

class WelcomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "redirects to the first created open channel" do
    get root_url

    assert_redirected_to channel_url(Channel.opens.order(:created_at).first)
  end

  test "redirects to the first created open channel, no matter what the last visited channel was" do
    cookies[:last_channel] = channels(:watercooler).id

    get root_url

    assert_redirected_to channel_url(Channel.opens.order(:created_at).first)
  end

  test "falls back to the last visited channel when no active open channel exists" do
    Channel.opens.update_all(active: false)
    cookies[:last_channel] = channels(:watercooler).id

    get root_url

    assert_redirected_to channel_url(channels(:watercooler))
  end
end
