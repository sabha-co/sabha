# frozen_string_literal: true

require_relative "../test_helper"

# sabha.co's own workspaces are already in the member's list, so they never
# suggest adding themselves to it.
class HubListPromptSaasTest < ActionDispatch::IntegrationTest
  test "a workspace sidebar and profile carry no sabha.co prompt" do
    alice = global_identities(:alice)
    sign_in_global_identity(alice)

    with_provisioned_workspace(name: "Prompt-free", creator: alice) do |workspace|
      workspace_get "/users/me/sidebar", workspace: workspace
      assert_response :success
      assert_select "#hub_list_prompt", count: 0

      workspace_get "/users/me/profile", workspace: workspace
      assert_response :success
      assert_select "a[href*='source=prompt']", count: 0
    end
  end

  test "the dismissal route doesn't exist on sabha.co" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/users/me/hub_list_prompt", method: :delete)
    end
  end
end
