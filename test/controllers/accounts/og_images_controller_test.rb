require "test_helper"

begin
  require "vips"
rescue LoadError
  Vips = nil
end

class Accounts::OgImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    skip "libvips is not available" unless defined?(::Vips)
  end

  test "renders a 1200x630 png card without authentication" do
    get account_og_image_url

    assert_equal "image/png", @response.headers["content-type"]

    image = ::Vips::Image.new_from_buffer(@response.body, "")
    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "is publicly cacheable" do
    get account_og_image_url

    assert_match "public", @response.headers["cache-control"]
  end

  test "returns 304 when the account is unchanged" do
    get account_og_image_url
    etag = @response.headers["etag"]

    get account_og_image_url, headers: { "If-None-Match" => etag }

    assert_response :not_modified
  end
end
