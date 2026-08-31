require "application_system_test_case"

class InboxThreadsTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:pets)
    parent = @room.messages.create!(body: "Thread root", creator: users(:jason), client_message_id: "mobile_thread_root")
    @thread = Rooms::Thread.create!(parent_message: parent, creator: users(:jason))
    @thread.memberships.grant_to(users(:david))
    @thread.messages.create!(body: "Thread reply", creator: users(:jason), client_message_id: "mobile_thread_reply")

    sign_in "david@37signals.com"
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "on a phone a thread card hides its last-reply timestamp" do
    page.current_window.resize_to(390, 800)
    visit inbox_threads_path

    card = find(".thread-card", text: "Thread root")
    within card do
      assert_selector ".thread__count", text: "1 reply", visible: true
      assert_selector "turbo-frame button", text: /Follow/, visible: true
      assert_no_selector ".txt-muted", text: /Last reply/, visible: true
    end
  end
end
