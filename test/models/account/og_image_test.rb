require "test_helper"

begin
  require "vips"
rescue LoadError
  Vips = nil
end

class Account::OgImageTest < ActiveSupport::TestCase
  setup do
    skip "libvips is not available" unless defined?(::Vips)
  end

  test "renders a 1200x630 card from the stock mark and account name" do
    image = render(accounts(:signal))

    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "composites the uploaded logo into the card" do
    accounts(:signal).logo.attach(
      io: File.open(file_fixture("moon.jpg")), filename: "moon.jpg", content_type: "image/jpeg")

    image = render(accounts(:signal))

    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "degrades to the stock mark when the logo blob is unreadable" do
    accounts(:signal).logo.attach(
      io: StringIO.new("this is not an image"), filename: "broken.png", content_type: "image/png")

    image = render(accounts(:signal))

    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "frames a non-square logo without raising or resizing the card" do
    wide = (::Vips::Image.black(400, 100) + [ 60, 90, 200 ]).cast("uchar")
    accounts(:signal).logo.attach(
      io: StringIO.new(wide.write_to_buffer(".png")), filename: "wide.png", content_type: "image/png")

    image = render(accounts(:signal))

    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "renders names containing pango markup characters without raising" do
    accounts(:signal).update!(name: "ACME & Co <chat>")

    image = render(accounts(:signal))

    assert_equal 1200, image.width
    assert_equal 630, image.height
  end

  test "falls back to the app name when the account name is blank" do
    account = accounts(:signal)

    account.update_column(:name, "")
    blank = Account::OgImage.new(account).png

    account.update_column(:name, Branding.app_name)
    named = Account::OgImage.new(account).png

    assert_equal named, blank
  end

  private
    def render(account)
      ::Vips::Image.new_from_buffer(Account::OgImage.new(account).png, "")
    end
end
