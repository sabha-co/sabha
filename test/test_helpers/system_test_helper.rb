module SystemTestHelper
  def sign_in(email_address, password = "secret123456")
    # Unauthenticated root redirects straight to the sign-in form (no interstitial
    # "Sign In" link), and the password form's submit button reads "Sign in".
    visit root_url

    fill_in "email_address", with: email_address
    fill_in "password", with: password

    click_on "Sign in"
    wait_for_network_idle!
    assert_selector ".rooms", wait: 5  # Wait for sidebar to load
  end

  def wait_for_cable_connection
    assert_selector "turbo-cable-stream-source[connected]", minimum: 1, visible: false
  end

  def join_room(room)
    retries = 0
    begin
      visit room_url(room)
      wait_for_network_idle!
      wait_for_cable_connection
      dismiss_pwa_install_prompt
    rescue RuntimeError => e
      # Cuprite wraps ObsoleteNode errors in RuntimeError during Turbo navigation
      raise e unless e.message.include?("ObsoleteNode") || e.message.include?("Cuprite")
      retries += 1
      sleep 0.5
      retry if retries < 3
      raise e
    end
  end

  def send_message(message)
    fill_in_rich_text_area "message_body", with: message
    click_on "send"
  end

  def within_message(message, &block)
    within "#" + dom_id(message), &block
  end

  def assert_message_text(text, **options)
    assert_selector ".message__body", text: text, **options
  end

  def assert_room_read(room)
    assert_selector ".rooms a:not(.unread)", text: "#{room.name}", wait: 5
  end

  def assert_room_unread(room)
    assert_selector ".rooms a", class: "unread", text: "#{room.name}", wait: 5
  end

  def reveal_message_actions
    begin
      find(".options-btn").click
    rescue Capybara::ElementNotFound
      find(".options-btn", visible: false).hover.click
    end
    assert_selector ".message__boost-btn", visible: true
  end

  def dismiss_pwa_install_prompt
    if page.has_css?("[data-pwa-install-target~='dialog']", visible: :visible, wait: 1)
      click_on("Close")
    end
  end

  def wait_for_network_idle!(timeout: 5)
    page.driver.wait_for_network_idle(timeout:)
  rescue Ferrum::TimeoutError
    # Continue if network doesn't fully idle - some ActionCable connections stay open
  end
end
