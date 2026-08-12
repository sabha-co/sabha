require "application_system_test_case"

# The workspace-header filter narrows the sidebar's room and person rows as
# you type. Filtering is presentational (rows hide, nothing reloads), so
# clearing the field must restore every row.
class SidebarFilterTest < ApplicationSystemTestCase
  setup { sign_in "kevin@37signals.com" }

  test "typing filters rooms and people, clearing restores them" do
    within ".rooms" do
      assert_link "Designers"
      assert_link "HQ"
    end

    find(".sidebar__filter-input").fill_in with: "desig"

    within ".rooms" do
      assert_link "Designers"
      assert_no_link "HQ"
    end
    assert_no_selector "#direct_rooms .direct"

    find(".sidebar__filter-input").fill_in with: "David"

    within ".rooms" do
      assert_no_link "Designers"
    end
    assert_selector "#direct_rooms .direct", text: "David"

    find(".sidebar__filter-input").send_keys(*([ :backspace ] * "David".length))

    within ".rooms" do
      assert_link "Designers"
      assert_link "HQ"
    end
    assert_selector "#direct_rooms .direct", text: "David"
  end

  test "escape clears the filter" do
    find(".sidebar__filter-input").fill_in with: "zzz-no-match"

    within ".rooms" do
      assert_no_link "Designers"
    end

    find(".sidebar__filter-input").send_keys :escape

    within ".rooms" do
      assert_link "Designers"
    end
    assert_equal "", find(".sidebar__filter-input").value
  end
end
