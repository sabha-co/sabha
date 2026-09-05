require "application_system_test_case"

# Room info and thread panels open on demand. Each docks only when its own
# width fits beside the sidebar and a readable transcript; otherwise it overlays
# the conversation without shrinking it.
class ContextualPanelTest < ApplicationSystemTestCase
  setup do
    page.current_window.resize_to(1400, 1400)
    sign_in "kevin@37signals.com"
    page.execute_script("Object.keys(localStorage).filter(key => key.startsWith('room-info:')).forEach(key => localStorage.removeItem(key))")
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "room info toggles both triggers and restores keyboard focus" do
    join_room rooms(:designers)
    find("a.navbar-roster--avatars").click
    assert_selector "#thread-panel[aria-label='Room info']"
    assert_selector "a.navbar-roster[aria-expanded='true']", count: 2
    assert_selector "#thread-panel .thread-panel__title:focus"
    find("a.navbar-roster.btn").click
    assert_no_selector "#thread-panel:not([hidden])"
    assert_selector "a.navbar-roster[aria-expanded='false']", count: 2
    assert_selector "a.navbar-roster.btn:focus"
  end

  test "an explicitly opened roster follows desktop room navigation but never opens a phone overlay" do
    join_room rooms(:designers)
    find("a.navbar-roster.btn").click
    assert_selector "#thread-panel .roster"
    visit room_path(rooms(:hq))
    assert_selector "#thread-panel .thread-panel__name", text: rooms(:hq).name
    page.current_window.resize_to(1100, 900)
    visit room_path(rooms(:designers))
    assert_no_selector "#thread-panel:not([hidden])"
    page.current_window.resize_to(390, 844)
    visit room_path(rooms(:hq))
    assert_no_selector "#thread-panel:not([hidden])"
  end

  test "notification selection updates the menu immediately" do
    join_room rooms(:designers)
    find("a.navbar-roster.btn").click
    find(".roster__notification-trigger").click
    within ".roster__notification-menu:popover-open" do
      click_button "Notifications muted"
    end
    assert_selector ".roster__notification-trigger", text: "Notifications muted"
    find(".roster__notification-trigger").click
    assert_selector "button[role='menuitemradio'][aria-checked='true']", text: "Notifications muted"
    assert_selector "button[role='menuitemradio']:focus", text: "Notifications muted"
    page.driver.browser.keyboard.type(:Home)
    assert_selector "button[role='menuitemradio']:focus", text: "Mentions only"
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector ".roster__notification-menu:popover-open"
    assert_selector ".roster__notification-trigger:focus"
    assert_selector "#thread-panel:not([hidden])"
    page.driver.browser.keyboard.type(:Escape)
    assert_no_selector "#thread-panel:not([hidden])"
    assert_selector "a.navbar-roster.btn:focus"
  end

  test "the avatar group opens room info and phones keep one compact entry point" do
    join_room rooms(:designers)

    within ".navbar-actions" do
      assert_selector "a", count: 2
      find(".navbar-member-avatars").click
    end
    assert_selector "#thread-panel .roster"
    find("[aria-label='Close room info']").click
    assert_no_selector "#thread-panel:not([hidden])"

    page.current_window.resize_to(390, 844)
    within ".navbar-actions" do
      assert_selector "a", count: 1
      assert_no_selector ".navbar-member-avatars"
      find("a.navbar-roster").click
    end
    assert_selector "#thread-panel .roster"
    assert_current_path room_path(rooms(:designers))
  end

  test "room info is closed by default and overlays below its inline threshold" do
    join_room rooms(:designers)

    assert_no_selector "#thread-panel:not([hidden])"

    page.current_window.resize_to(1160, 900)
    find("a.navbar-roster.btn").click
    assert_selector "#thread-panel .roster", wait: 5
    assert_panel_position "static"

    page.current_window.resize_to(1159, 900)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    page.current_window.resize_to(500, 800)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    assert page.evaluate_script("document.body.classList.contains('thread-panel-open')")
    page.driver.browser.mouse.click(x: 70, y: 400)
    assert_no_selector "#thread-panel:not([hidden])"
  end

  test "a thread docks only at its wider threshold and fills a phone column" do
    Rooms::Thread.create!(parent_message: messages(:third), creator: users(:david))
      .messages.create!(creator: users(:david), body: "A thread reply")

    join_room rooms(:designers)

    page.current_window.resize_to(1232, 900)
    find("##{dom_id(messages(:third))}").hover
    find("##{dom_id(messages(:third))} .message__reply-btn").click
    assert_selector "#thread-panel .thread-panel__title", text: "Thread", wait: 5
    assert_selector "#thread-panel[aria-label='Thread']"
    assert_panel_position "static"

    page.current_window.resize_to(1231, 900)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    page.current_window.resize_to(500, 800)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    page.current_window.resize_to(499, 800)
    # Phone: the panel becomes the whole column — full-bleed from the left edge,
    # no scrim behind it.
    panel = find("#thread-panel")
    assert_equal 0, panel.evaluate_script("Math.round(this.getBoundingClientRect().left)")
    assert_equal page.evaluate_script("window.innerWidth"),
                 panel.evaluate_script("Math.round(this.getBoundingClientRect().width)")
    assert_selector "#thread-panel .thread-panel__room[data-turbo-frame='_top']", text: "in Designers"
    assert_no_selector ".thread-panel__scrim", visible: :visible
  end

  test "a forum post keeps its wider reading column" do
    forum = rooms(:help_desk)
    forum.memberships.grant_to(users(:kevin))
    post = Current.set(user: users(:david)) { forum.post!(title: "A question", body: "A question") }

    join_room forum

    page.current_window.resize_to(1232, 900)
    find("##{dom_id(post, :card)}").click
    assert_selector "#thread-panel .forum-post-header", wait: 5
    assert_panel_position "static"
    # A forum post reads wider than a thread's 360px column, up to the 680px cap.
    width = find("#thread-panel").evaluate_script("Math.round(this.getBoundingClientRect().width)")
    assert_operator width, :>, 360
    assert_operator width, :<=, 680
  end

  private
    def assert_panel_position(position)
      assert_equal position, find("#thread-panel").evaluate_script("getComputedStyle(this).position")
    end
end
