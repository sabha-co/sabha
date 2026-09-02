require "application_system_test_case"

class BookmarksTest < ApplicationSystemTestCase
  setup do
    @message = rooms(:pets).messages.create!(
      body: "Bookmark typography marker",
      creator: users(:jason),
      client_message_id: "bookmark_typography_marker"
    )
    Bookmark.create!(user: users(:david), message: @message)

    sign_in "david@37signals.com"
  end

  test "bookmark cards use the handoff's compact hierarchy" do
    visit inbox_bookmarks_path

    card = find(".bookmark-card", text: "Bookmark typography marker")
    room = card.find(".bookmark-card__room")
    saved = card.find(".bookmark-card__saved")
    preview = card.find(".bookmark-card__content > .lexxy-content")

    assert_equal "13px", room.evaluate_script("getComputedStyle(this).fontSize")
    assert_equal "600", room.evaluate_script("getComputedStyle(this).fontWeight")
    assert_equal "12.5px", saved.evaluate_script("getComputedStyle(this).fontSize")
    assert_equal "14.5px", preview.evaluate_script("getComputedStyle(this).fontSize")
  end
end
