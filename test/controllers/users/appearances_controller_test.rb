require "test_helper"

class Users::AppearancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "show renders the theme control inside the settings shell" do
    get user_appearance_url

    assert_response :success
    assert_select ".settings-nav__item[aria-current=page]", text: "Appearance"
    assert_select "[data-controller=theme] [data-action*=?]", "theme#setLight"
  end

  test "show renders the density control inside the settings shell" do
    get user_appearance_url

    assert_response :success
    assert_select "[data-controller=density] [data-action*=?]", "density#setOn"
  end

  test "show renders the typeface control inside the settings shell" do
    get user_appearance_url

    assert_response :success
    assert_select "[data-controller=typeface] [data-action*=?]", "typeface#setOn"
  end

  test "show renders the sidebar skin control inside the settings shell" do
    get user_appearance_url

    assert_response :success
    assert_select "[data-controller=sidebar-skin] [data-action*=?]", "sidebar-skin#setOn"
  end

  test "show lists the personal sections in the shell nav" do
    get user_appearance_url

    assert_select ".settings-nav__item", text: "Profile"
    assert_select ".settings-nav__item", text: "Appearance"
    assert_select ".settings-nav__item", text: "Notifications"
    assert_select ".settings-nav__item", text: "Account"
  end
end
