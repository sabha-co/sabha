require "test_helper"

class API::Bots::Messages::CreatesTest < ActionDispatch::IntegrationTest
  setup do
    skip "libvips is not available" unless defined?(::Vips)

    @bot = users(:bender)
    @room = rooms(:watercooler)
  end

  test "create file" do
    post api_bots_room_messages_url(@room), params: {
      attachment: fixture_file_upload("moon.jpg", "image/jpeg")
    }, headers: bot_headers(@bot.bot_key)

    assert_response :created
  end
end
