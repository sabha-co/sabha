require "test_helper"

class Messages::ByBotsControlleTest < ActionDispatch::IntegrationTest
  setup do
    skip "libvips is not available" unless defined?(::Vips)

    @room = rooms(:designers)
    sign_in :david
  end

  test "create file" do
    post room_bot_messages_url(@room, "example"), params: {
      attachment: fixture_file_upload("moon.jpg", "image/jpeg")
    }

    assert_response :created
  end
end
