require "application_system_test_case"

class HeaderStreamAuditTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:designers)
    @room.update!(description: "A room for discussing design decisions and sharing work in progress.")
    @first = @room.messages.create!(creator: users(:jason), body: "Audit first message", created_at: Time.current.change(hour: 12))
    @second = @room.messages.create!(creator: users(:jason), body: "Audit follow-on message", created_at: @first.created_at + 1.minute)
    catch_up @room.memberships.find_by!(user: users(:kevin))
    sign_in "kevin@37signals.com"
    click_on "Designers"
    dismiss_pwa_install_prompt
  end

  teardown do
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
    page.current_window.resize_to(1400, 1400)
  end

  test "title and topic open room details and the narrow header drops the topic" do
    find(".navbar-title a").click
    assert_selector "#thread-panel .roster__topic", text: @room.description
    find("[aria-label='Close room info']").click
    find(".navbar-topic").click
    assert_selector "#thread-panel .roster__topic", text: @room.description
    find("[aria-label='Close room info']").click
    page.current_window.resize_to(834, 900)
    assert_equal "none", find(".navbar-topic", visible: :all).evaluate_script("getComputedStyle(this).display")
  end

  test "grouped rows expose a timestamp on hover and keyboard focus" do
    row = find("##{dom_id(@second)}.message--threaded")
    row.hover
    assert_selector "##{dom_id(@second)} .message__grouped-time", visible: true
    time = row.find(".message__grouped-time")
    time.evaluate_script("this.focus()")
    find("#nav").hover
    assert_selector "##{dom_id(@second)} .message__grouped-time:focus", visible: true
    page.save_screenshot(Rails.root.join("tmp/header-stream-desktop.png")) if ENV["AUDIT_SCREENSHOTS"]
  end

  test "an unread cursor inside a day does not repeat its date" do
    visit room_path(rooms(:hq))
    rewind_unread_to @room.memberships.find_by!(user: users(:kevin)), @second, marked: true
    visit room_path(@room)
    assert_selector "##{dom_id(@second)} .message__new-separator"
    assert_no_selector "##{dom_id(@second)} .message__day-separator", visible: true
    assert_selector ".message--first-of-day .message__day-separator", visible: true
  end

  test "wide message bodies respect the reading measure" do
    [ 1400, 1100, 1024 ].each do |width|
      page.current_window.resize_to(width, 900)
      body = find("##{dom_id(@first)} .message__body-content")
      within_measure = body.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement('span')
        probe.style.cssText = 'position:absolute;width:80ch'
        this.append(probe)
        const measure = probe.getBoundingClientRect().width
        probe.remove()
        return this.getBoundingClientRect().width <= measure + 1
      })()
      JS
      assert within_measure, "message body exceeds 80ch at #{width}px"
    end
  end

  test "the floating action bar sits at the row's right edge, not at the measure" do
    page.current_window.resize_to(1400, 900)
    row = find("##{dom_id(@first)}")
    at_row_edge = row.evaluate_script(<<~JS)
      (() => {
        const bar = this.querySelector('.message__meta .message__actions')
        const content = this.querySelector('.message__body-content')
        const gutter = parseFloat(getComputedStyle(this).paddingInlineEnd)
        return this.getBoundingClientRect().right - bar.getBoundingClientRect().right <= gutter + 1 &&
          bar.getBoundingClientRect().right > content.getBoundingClientRect().right
      })()
    JS
    assert at_row_edge, "action bar is anchored to the reading measure instead of the row"
  end

  test "a touch user can open reactions directly from a message" do
    page.current_window.resize_to(390, 844)
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    assert page.evaluate_script("matchMedia('(hover: none) and (pointer: coarse)').matches")
    assert page.evaluate_script(<<~JS), "metadata overlaps the touch controls"
      Array.from(document.querySelectorAll('.message:not(.message--threaded) .message__meta')).every(meta => {
        const heading = meta.querySelector('.message__heading')
        const actions = meta.querySelector('.message__actions')
        const edge = actions.getBoundingClientRect().left
        return Array.from(heading.children).filter(el => el.getClientRects().length)
          .every(el => el.getBoundingClientRect().right <= edge + 1)
      })
    JS
    row = find("##{dom_id(@first)}")
    row.find(".message__reaction-picker > button").click
    assert_selector ".message-reaction-menu:popover-open"
    within ".message-reaction-menu:popover-open" do
      click_button "Thumbs up"
    end
    assert_selector "##{dom_id(@first)} .boost--mine", text: "👍"
    page.save_screenshot(Rails.root.join("tmp/header-stream-touch.png")) if ENV["AUDIT_SCREENSHOTS"]
  end

  test "thread authors retain a readable name beside edited and mention metadata" do
    users(:jason).update!(name: "Moderator")
    @first.update!(body: "<div>Hi #{mention_attachment_for(:kevin)}</div>")
    @first.update_columns(updated_at: @first.created_at + 1.minute)
    Rooms::Thread.create!(parent_message: @first, creator: users(:kevin))
    visit room_path(@room)
    page.current_window.resize_to(390, 844)
    find("##{dom_id(@first)}").hover
    find("##{dom_id(@first)} .message__reply-btn").click
    assert_selector "#thread-panel [data-panel-kind='thread']"
    assert_selector "#thread-panel .message__edited", text: "(edited)"
    assert_selector "#thread-panel .message__mention-label", text: /mentioned you/i
    author = find("#thread-panel .message__author", text: "Moderator")
    assert author.evaluate_script("this.clientWidth >= this.scrollWidth"), "author lost its name before optional metadata"
  end

  test "composer growth keeps the newest phone message visible without pulling a history reader down" do
    latest = nil
    25.times do |i|
      latest = @room.messages.create!(creator: users(:jason), body: "Phone history #{i} " * 8, created_at: @second.created_at + (i + 1).minutes)
    end
    catch_up @room.memberships.find_by!(user: users(:kevin))
    page.current_window.resize_to(390, 844)
    visit room_path(@room)
    dismiss_pwa_install_prompt
    assert_selector "##{dom_id(latest)}", visible: :all
    settle_layout
    assert_bottom
    execute_script "document.querySelector('#composer').style.minHeight = '280px'"
    settle_layout
    assert_bottom

    execute_script "document.querySelector('#message-area .messages').scrollTop -= 250"
    settle_layout
    before = page.evaluate_script("document.querySelector('#message-area .messages').scrollTop")
    execute_script "document.querySelector('#composer').style.minHeight = '320px'"
    settle_layout
    assert_in_delta before, page.evaluate_script("document.querySelector('#message-area .messages').scrollTop"), 4
  end

  test "scrolling up during message growth releases the newest anchor" do
    25.times do |i|
      @room.messages.create!(creator: users(:jason), body: "Resize history #{i} " * 8, created_at: @second.created_at + (i + 1).minutes)
    end
    catch_up @room.memberships.find_by!(user: users(:kevin))
    page.current_window.resize_to(390, 844)
    visit room_path(@room)
    dismiss_pwa_install_prompt
    settle_layout
    assert_bottom

    execute_script <<~JS
      const row = document.querySelector('#message-area .messages').lastElementChild
      row.style.minHeight = `${row.getBoundingClientRect().height + 200}px`
    JS
    settle_layout
    assert_bottom
    execute_script "document.querySelector('#message-area .messages').lastElementChild.style.minHeight = ''"
    settle_layout
    assert_bottom

    positions = page.evaluate_async_script(<<~JS)
      const done = arguments[0], container = document.querySelector('#message-area .messages')
      requestAnimationFrame(() => {
        const row = container.lastElementChild
        row.style.minHeight = `${row.getBoundingClientRect().height + 200}px`
        container.scrollTop -= 300
        const intendedTop = container.scrollTop
        requestAnimationFrame(() => requestAnimationFrame(() => done([intendedTop, container.scrollTop])))
      })
    JS
    assert_operator positions.last, :<=, positions.first + 4, "resize anchoring overrode the upward scroll"
  end

  private
    def settle_layout
      page.evaluate_async_script("const done = arguments[0]; document.fonts.ready.then(() => requestAnimationFrame(() => requestAnimationFrame(done)))")
    end

    def assert_bottom
      distance = page.evaluate_script("(() => { const el = document.querySelector('#message-area .messages'); return el.scrollHeight - el.clientHeight - el.scrollTop })()")
      assert_operator distance, :<=, 4, "newest message is #{distance}px below the viewport"
    end
end
