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

  test "points at a configured sabha.co" do
    with_env("SABHA_HUB_URL" => "https://hub.example/") do
      get user_sidebar_url
    end

    assert_select "#hub_list_nudge a[href^='https://hub.example/remote_workspaces/new?']"
    assert_select "#hub_list_nudge .sidebar__tool-label", "hub.example"
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

  private
    def with_env(vars)
      originals = vars.keys.index_with { ENV[it] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      originals.each { |key, value| ENV[key] = value }
    end
end
