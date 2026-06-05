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

  test "falls back to the app name when the account name is blank" do
    accounts(:signal).update_column(:name, "")

    assert_nothing_raised { render(accounts(:signal)) }
  end

  private
    def render(account)
      ::Vips::Image.new_from_buffer(Account::OgImage.new(account).png, "")
    end
end
