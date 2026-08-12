require "application_system_test_case"

# Regression wall for the four primary inbox surfaces the v2 reskin restyles.
# They are fully built (real query objects, live streams); this only guards that
# each one still renders under its heading after the reskin. Asserts the nav
# heading (an <h1>), a semantic contract the redesign keeps, rather than layout.
class InboxSurfacesTest < ApplicationSystemTestCase
  setup { sign_in "david@37signals.com" }

  test "activity, threads, bookmarks and direct-messages inboxes each render" do
    visit inbox_activity_index_path
    assert_selector "h1", text: "Activity"

    visit inbox_threads_path
    assert_selector "h1", text: "Threads"

    visit inbox_bookmarks_path
    assert_selector "h1", text: "Bookmarks"

    visit inbox_direct_messages_path
    assert_selector "h1", text: "Direct"   # "Direct Messages" on desktop
  end
end
