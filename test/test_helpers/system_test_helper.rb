module SystemTestHelper
  def sign_in(email_address, password = "secret123456")
    visit root_url  # unauthenticated root redirects straight to the sign-in form

    fill_in "email_address", with: email_address
    fill_in "password", with: password

    click_on "Sign in"
    wait_for_network_idle!
    assert_selector ".rooms", wait: 5  # Wait for sidebar to load
  end

  def wait_for_cable_connection
    # Capybara auto-waits and reloads stale elements, but that reload does NOT
    # cover Cuprite's ObsoleteNode when Turbo replaces the whole document
    # mid-check — a plain `assert_selector ..., wait: 20` still failed ~1 in 3
    # full-suite runs. So poll and tolerate ObsoleteNode explicitly. (Per-assertion
    # wait only; the global default_max_wait_time stays 5 so negative assertions
    # aren't slowed.)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    loop do
      begin
        return if has_selector?("turbo-cable-stream-source[connected]", visible: false, wait: 1)
      rescue RuntimeError => e
        raise unless e.message.include?("ObsoleteNode") || e.message.include?("Cuprite")
        # node replaced during a Turbo render — re-query on the next pass
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise Capybara::ExpectationNotMet, "turbo-cable-stream-source[connected] did not appear within 20s"
      end
    end
  end

  def join_room(room)
    attempts = 0
    begin
      visit room_url(room)
      wait_for_network_idle!
      wait_for_cable_connection
      dismiss_pwa_install_prompt
    rescue Capybara::ExpectationNotMet, RuntimeError => e
      # Retry the whole navigation, not a manual sleep-poll. Cuprite raises
      # ObsoleteNode when Turbo replaces the document mid-navigation — that is a
      # full-page swap, outside Capybara's element auto-reload — and the cable
      # handshake can outrun even a generous wait under load. Re-navigate; the
      # assertions inside auto-wait, so no explicit sleep is needed.
      raise e unless e.is_a?(Capybara::ExpectationNotMet) ||
                     e.message.include?("ObsoleteNode") || e.message.include?("Cuprite")
      raise e if (attempts += 1) >= 4
      retry
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
