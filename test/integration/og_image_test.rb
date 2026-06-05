require "test_helper"

class OgImageTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "og:image points at the rendered account card with an absolute url" do
    get room_url(rooms(:watercooler))

    assert_select "meta[property='og:image']" do |tags|
      assert_match %r{\Ahttps?://.+#{Regexp.escape(account_og_image_path)}}, tags.first["content"]
    end
  end

  test "still uses the card endpoint once a logo is uploaded" do
    accounts(:signal).update! logo: fixture_file_upload("moon.jpg", "image/jpeg")

    get room_url(rooms(:watercooler))

    assert_select "meta[property='og:image']" do |tags|
      assert_includes tags.first["content"], account_og_image_path
    end
  end
end
