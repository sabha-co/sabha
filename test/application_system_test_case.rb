require "test_helper"
require "capybara/cuprite"
require_relative "test_helpers/system_test_helper"
require_relative "test_helpers/rich_text_editor_helper"

WebMock.disable!

# Configure Capybara
Capybara.default_max_wait_time = 5
Capybara.default_normalize_ws = true
Capybara.disable_animation = true

# Register Cuprite driver with sensible defaults
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    headless: !ENV["HEADLESS"].in?(%w[0 false]),
    process_timeout: 15,
    timeout: 10,
    inspector: true,
    pending_connection_errors: false,  # ActionCable keeps WebSocket connections open
    browser_options: {
      "disable-smooth-scrolling" => true,
      "disable-dev-shm-usage" => true
    }
  )
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite

  include SystemTestHelper
  include RichTextEditorHelper

  def pause
    page.driver.pause
  end

  def debug(binding = nil)
    $stdout.puts "Opening Chrome DevTools inspector..."
    page.driver.debug(binding)
  end
end
