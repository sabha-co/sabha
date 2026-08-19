require "test_helper"

class Inboxes::DirectMessagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }

  test "index opens the new-message compose screen from a header button, not an inline rail form" do
    get inbox_direct_messages_url

    assert_response :success
    assert_select ".dm-rail__header a[href=?][data-turbo-frame='_top']", new_rooms_direct_path
    assert_select "form.dm-compose", count: 0
  end
end
