require "test_helper"

class ApplicationPlatformTest < ActiveSupport::TestCase
  test "a headless browser is an automated client" do
    headless = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/128.0.0.0 Safari/537.36"

    assert ApplicationPlatform.new(headless).automated?
  end

  test "a desktop browser is not an automated client" do
    chrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    assert_not ApplicationPlatform.new(chrome).automated?
  end
end
