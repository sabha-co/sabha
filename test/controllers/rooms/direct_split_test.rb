require "test_helper"

# The DM split view: direct rooms and the DM inbox share a conversation-list
# rail beside the open conversation, and direct-room headers carry the other
# person's presence instead of the generic room chrome.
class Rooms::DirectSplitTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "a direct room renders the conversation rail" do
    get room_url(rooms(:david_and_kevin))

    assert_response :success
    assert_select "#list-rail #inbox .dm-conversation", minimum: 2
    assert_select "#list-rail .dm-rail__title", text: "Direct messages"
  end

  test "a 1:1 header shows presence and a View profile button, and drops the roster" do
    get room_url(rooms(:david_and_kevin))

    assert_select ".navbar-dm__status"
    assert_select "a.btn.navbar-view-profile[href=?]", user_path(users(:kevin)), text: "View profile"
    assert_select "a[href$=?]", "/roster", count: 0
  end

  test "a group DM header shows the member count and no View profile" do
    group = Current.set(user: users(:david)) do
      Rooms::Direct.find_or_create_for([ users(:david), users(:jason), users(:kevin) ])
    end

    get room_url(group)

    assert_select "a.navbar-people", text: /3 people/
    assert_select "a", text: "View profile", count: 0
  end

  test "a note-to-self header shows neither presence nor View profile" do
    solo = Current.set(user: users(:david)) do
      Rooms::Direct.find_or_create_for([ users(:david) ])
    end

    get room_url(solo)

    assert_select ".navbar-dm__status", count: 0
    assert_select "a", text: "View profile", count: 0
  end

  test "non-direct rooms get no conversation rail" do
    get room_url(rooms(:pets))

    assert_select "#list-rail", count: 0
  end

  test "the DM inbox renders the rail beside a select-a-conversation pane" do
    get inbox_direct_messages_url

    assert_response :success
    assert_select "#list-rail #inbox .dm-conversation", minimum: 2
    assert_select "#main-content .dm-empty-pane"
  end

  test "rail rows keep the live-update contract" do
    get room_url(rooms(:david_and_kevin))

    assert_select "#list-rail #inbox[data-controller=dm-list]"
    assert_select "#list-rail turbo-cable-stream-source"
    assert_select "#inbox .dm-conversation[id=?]",
                  ActionView::RecordIdentifier.dom_id(rooms(:david_and_jason), :dm_inbox)
  end

  test "an open conversation that's fallen off the first page is pinned above the rail" do
    # Give david more recent DMs than a page holds, so an older one drops off.
    stale = create_direct_with("old-friend@example.com")
    stale.update!(last_active_at: 1.year.ago)

    10.times do |i|
      create_direct_with("pal#{i}@example.com").update!(last_active_at: i.minutes.ago)
    end

    get room_url(stale)

    assert_response :success
    dom = ActionView::RecordIdentifier.dom_id(stale, :dm_inbox)
    # Pinned above the paginated list and marked current...
    assert_select ".dm-list--pinned .dm-conversation.dm-conversation--current[id=?]", dom
    # ...and not duplicated inside the paginated first page.
    assert_select "#inbox .dm-conversation[id=?]", dom, count: 0
  end

  test "an open conversation on the first page is not pinned" do
    get room_url(rooms(:david_and_kevin))

    assert_response :success
    assert_select ".dm-list--pinned", count: 0
  end

  private
    def create_direct_with(email)
      other = User.create!(name: email.split("@").first, email_address: email, password: "secret123456")
      Current.set(user: users(:david)) { Rooms::Direct.find_or_create_for([ users(:david), other ]) }
    end
end
