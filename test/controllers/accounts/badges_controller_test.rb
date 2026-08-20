require "test_helper"

class Accounts::BadgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "index badges" do
    get account_badges_url
    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Badges"
  end

  test "index renders badge rows and the New badge control" do
    get account_badges_url

    assert_select "#badge_#{badges(:founder).id} .badge-row__chip", text: "Founder"
    assert_select "a[href=?]", new_account_badge_path, text: /New badge/
  end

  test "non-admins cannot index badges" do
    sign_in :kevin
    get account_badges_url

    assert_response :forbidden
    assert_select ".empty-state__title", text: "Administrators only"
    assert_select "a[href=?]", account_path, text: "Back to community settings"
  end

  test "non-admin badge requests stay bare for Turbo frames, non-HTML GETs, and mutations" do
    sign_in :kevin

    get account_badges_url, headers: { "Turbo-Frame" => "settings-panel" }
    assert_response :forbidden
    assert_select ".empty-state__title", count: 0

    get account_badges_url(format: :json)
    assert_response :forbidden
    assert_equal "", response.body

    post account_badges_url, params: { badge: { name: "Hack", color: Badge::COLORS.first } }
    assert_response :forbidden
    assert_select ".empty-state__title", count: 0
  end

  test "new renders the editor form with the full palette" do
    get new_account_badge_url

    assert_response :success
    assert_select "turbo-frame#badge_editor"
    assert_select "h2", text: "New badge"
    assert_select ".swatch-grid .swatch", count: Badge::COLORS.size
  end

  test "edit renders the prefilled editor" do
    get edit_account_badge_url(badges(:staff))

    assert_response :success
    assert_select "h2", text: "Edit badge"
    assert_select "input[name='badge[name]'][value=?]", "Staff"
  end

  test "create badge normalises the name and stores the chosen hue" do
    assert_difference -> { Badge.count }, 1 do
      post account_badges_url, params: { badge: { name: "crew", color: "#1B8F53" } }
    end

    assert_redirected_to account_badges_url
    assert_equal "CREW", Badge.last.name
    assert_equal "#1B8F53", Badge.last.color
  end

  test "create badge with a blank name re-renders the editor with an error" do
    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "", color: "#1B8F53" } }
    end

    assert_response :unprocessable_entity
    assert_select ".field-error"
  end

  test "create badge with a duplicate name re-renders the editor with an error" do
    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: badges(:founder).name.downcase, color: "#1B8F53" } }
    end

    assert_response :unprocessable_entity
    assert_select ".field-error"
  end

  test "create badge with an off-palette colour is rejected" do
    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "Test", color: "#123456" } }
    end

    assert_response :unprocessable_entity
  end

  test "update badge" do
    badge = badges(:staff)
    patch account_badge_url(badge), params: { badge: { name: "crew", color: "#1B8F53" } }

    assert_redirected_to account_badges_url
    assert_equal "CREW", badge.reload.name
    assert_equal "#1B8F53", badge.color
  end

  test "update badge with a blank name re-renders the editor and leaves the badge intact" do
    badge = badges(:staff)
    patch account_badge_url(badge), params: { badge: { name: "", color: "#1B8F53" } }

    assert_response :unprocessable_entity
    assert_equal "Staff", badge.reload.name
  end

  test "non-admins cannot update badges" do
    sign_in :kevin
    patch account_badge_url(badges(:founder)), params: { badge: { name: "Hacked" } }

    assert_response :forbidden
    assert_equal "Founder", badges(:founder).reload.name
  end

  test "destroy badge" do
    badge = badges(:staff)

    assert_difference -> { Badge.count }, -1 do
      delete account_badge_url(badge)
    end

    assert_redirected_to account_badges_url
  end

  test "non-admins cannot create badges" do
    sign_in :kevin

    assert_no_difference -> { Badge.count } do
      post account_badges_url, params: { badge: { name: "Hack", color: Badge::COLORS.first } }
    end

    assert_response :forbidden
  end

  test "non-admins cannot destroy badges" do
    sign_in :kevin

    assert_no_difference -> { Badge.count } do
      delete account_badge_url(badges(:founder))
    end

    assert_response :forbidden
  end
end
