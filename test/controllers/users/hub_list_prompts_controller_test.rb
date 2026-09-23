require "test_helper"

class Users::HubListPromptsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }

  test "the sidebar offers to add the community to sabha.co" do
    get user_sidebar_url

    assert_select "#hub_list_nudge" do
      assert_select "a[href=?]", "https://sabha.co/remote_workspaces/new?origin=#{CGI.escape("http://www.example.com")}&source=prompt"
    end
  end

  test "don't show again removes the nudge for good" do
    delete user_hub_list_prompt_url, as: :turbo_stream

    assert_turbo_stream action: :remove, target: "hub_list_nudge"
    assert users(:david).reload.hub_list_prompt_dismissed?

    get user_sidebar_url
    assert_select "#hub_list_nudge", count: 0
  end

  test "the profile keeps its link after the nudge is dismissed" do
    users(:david).dismiss_hub_list_prompt

    get user_profile_url

    assert_select "a.setting-row[href^='https://sabha.co/remote_workspaces/new']", text: /Add .* to your sabha.co list/
  end

  test "the admin can stop suggesting sabha.co" do
    accounts(:signal).settings.suggest_hub_list = false
    accounts(:signal).save!

    get user_sidebar_url
    assert_select "#hub_list_nudge", count: 0

    get user_profile_url
    assert_select "a[href^='https://sabha.co/remote_workspaces']", count: 0
  end

  test "the Sabha apps don't get the nudge; they have the list already" do
    get user_sidebar_url, headers: { "Sabha-Client" => "desktop" }

    assert_select "#hub_list_nudge", count: 0
  end

  test "communities on their own single sign-on don't suggest sabha.co" do
    Account.stubs(:sso_auth?).returns(true)

    get user_sidebar_url

    assert_select "#hub_list_nudge", count: 0
  end
end
