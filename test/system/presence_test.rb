require "application_system_test_case"

class PresenceTest < ApplicationSystemTestCase
  setup do
    sign_in "david@37signals.com"
  end

  test "choosing a state updates your own dot and closes the menu" do
    open_profile_menu

    click_on "Do not disturb"

    assert_no_selector "[popover]:popover-open", wait: 5
    assert_selector "##{dom_id(users(:david), :presence_dot_sidebar)}.status--dnd"
    assert_equal "do_not_disturb", users(:david).reload.availability
  end

  test "the footer label follows the choice" do
    open_profile_menu
    click_on "Away"

    assert_selector ".sidebar__me-status", text: "Away"
  end

  test "the picker marks the current choice and says notifications are unchanged" do
    users(:david).update! availability: :away
    page.refresh
    open_profile_menu

    assert_selector "[role=radio][aria-checked=true]", text: "Away"
    assert_selector "[role=radio][aria-checked=false]", text: "Available"
    assert_text "notifications are unchanged"
  end

  # The point of the whole slice: a change made by one person reaches someone
  # else's screen. A stream keyed to the viewer would pass every other test here
  # and still fail this one. Asserted on the sidebar DM row, which is already on
  # screen after signing in — no navigation to race.
  test "another member's change reaches your DM row without a reload" do
    jason = users(:jason)
    assert_selector "##{dom_id(jason, :presence_dot_direct)}"

    using_session "jason" do
      sign_in "jason@37signals.com"
      open_profile_menu
      click_on "Do not disturb"
      assert_equal "do_not_disturb", jason.reload.availability
    end

    assert_selector "##{dom_id(jason, :presence_dot_direct)}.status--dnd", wait: 10
  end

  # A duplicate stream source is never confirmed by the server, so Action Cable's
  # guarantor resubscribes it every 500ms for the life of the tab. The sidebar and
  # the main document are separate renders that can't dedupe against each other,
  # so this is asserted against the assembled DOM rather than either response.
  # The layout carries your own presence stream; the pages that draw other
  # people's rarer surfaces add the workspace stream on top. Both are checked
  # here because that second subscription is exactly where a duplicate would
  # creep back in.
  test "no page subscribes to the same stream twice" do
    [ inbox_direct_messages_url, account_users_url, user_url(users(:jason)) ].each do |url|
      visit url

      names = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("turbo-cable-stream-source"))
             .map(el => el.getAttribute("signed-stream-name"))
      JS

      assert_predicate names, :any?, "expected #{url} to subscribe to something"
      assert_equal names.uniq.size, names.size,
                   "#{url}: #{names.size - names.uniq.size} duplicate stream source(s) — each one resubscribes forever"
    end
  end

  private
    def dom_id(...) = ActionView::RecordIdentifier.dom_id(...)

    def open_profile_menu
      find(".sidebar__me").click
      assert_selector "[role=radiogroup]", wait: 5
    end
end
