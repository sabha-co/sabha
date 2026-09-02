require "application_system_test_case"

class ActivityTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:pets)
    @room.update!(name: "Introductions")
    users(:jason).update!(name: "Moderator")
    @room.messages.create!(
      body: "<div>#{mention_attachment_for(:david)} Activity mobile marker</div>",
      creator: users(:jason),
      client_message_id: "activity_mobile_marker"
    )

    sign_in "david@37signals.com"
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "on a phone Activity metadata wraps between fields, not inside them" do
    page.current_window.resize_to(390, 800)
    visit inbox_activity_index_path

    row = find(".notification--activity", text: "Activity mobile marker")
    labels = row.evaluate_script(<<~JS)
      Array.from(this.querySelectorAll(".message__heading > strong, .notification__where")).map((element) => {
        const rect = element.getBoundingClientRect()
        return { text: element.textContent, width: rect.width, height: rect.height }
      })
    JS

    assert labels.all? { |label| label["height"] < 24 }, "expected one-line Activity labels: #{labels.inspect}"
  end

  test "Activity uses the handoff's compact metadata hierarchy" do
    visit inbox_activity_index_path

    row = find(".notification--activity", text: "Activity mobile marker")
    actor = row.find(".message__heading > strong")
    verb = row.find(".message__heading > .txt-muted")
    room = row.find(".notification__where")
    preview = row.find(".message__presentation .lexxy-content")

    assert_equal "14px", actor.evaluate_script("getComputedStyle(this).fontSize")
    assert_equal "700", actor.evaluate_script("getComputedStyle(this).fontWeight")
    assert_equal "13.5px", verb.evaluate_script("getComputedStyle(this).fontSize")
    assert_equal "13px", room.evaluate_script("getComputedStyle(this).fontSize")
    assert_equal "14px", preview.evaluate_script("getComputedStyle(this).fontSize")
  end
end
