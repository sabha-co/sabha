require "application_system_test_case"

# Room info and thread panels open on demand. Each docks only when its own
# width fits beside the sidebar and a readable transcript; otherwise it overlays
# the conversation without shrinking it.
class ContextualPanelTest < ApplicationSystemTestCase
  setup do
    page.current_window.resize_to(1400, 1400)
    sign_in "kevin@37signals.com"
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "room info is closed by default and overlays below its inline threshold" do
    join_room rooms(:designers)

    assert_no_selector "#thread-panel:not([hidden])"

    page.current_window.resize_to(1160, 900)
    find("a[href$='/roster']").click
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
    assert_panel_position "static"

    page.current_window.resize_to(1231, 900)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    page.current_window.resize_to(500, 800)
    assert_panel_position "fixed"
    assert_selector ".thread-panel__scrim", visible: :visible

    page.current_window.resize_to(499, 800)
    panel = find("#thread-panel")
    assert_equal 0, panel.evaluate_script("Math.round(this.getBoundingClientRect().left)")
    assert_equal 499, panel.evaluate_script("Math.round(this.getBoundingClientRect().width)")
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
    assert_equal 517, find("#thread-panel").evaluate_script("Math.round(this.getBoundingClientRect().width)")
  end

  private
    def assert_panel_position(position)
      assert_equal position, find("#thread-panel").evaluate_script("getComputedStyle(this).position")
    end
end
