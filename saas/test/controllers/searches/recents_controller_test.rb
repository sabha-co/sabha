# frozen_string_literal: true

require_relative "../../test_helper"

# The recent-search frame is a shared (non-SaaS-engine) route, so it also serves
# workspace-scoped requests. History lives in the tenant database, and user IDs
# repeat across tenants, so identical IDs in two workspaces must stay separate.
class Searches::RecentsControllerTest < ActionDispatch::IntegrationTest
  test "frame URLs keep the tenant prefix and history never crosses workspaces" do
    alice = global_identities(:alice)

    with_provisioned_workspace(name: "One", creator: alice) do |one|
      with_provisioned_workspace(name: "Two", creator: alice) do |two|
        seed_search(one, alice, "only in one")
        seed_search(two, alice, "only in two")

        sign_in_global_identity(alice)

        workspace_get "/searches/recents", workspace: one
        assert_response :success
        assert_match "only in one", response.body
        assert_no_match(/only in two/, response.body)

        workspace_get "/searches/recents", workspace: two
        assert_response :success
        assert_match "only in two", response.body
        assert_no_match(/only in one/, response.body)

        # The palette's frame src must stay workspace-scoped, or opening it in
        # one workspace would fetch another's history.
        workspace_get "/", workspace: one
        follow_redirect! while response.redirect?
        assert_select "turbo-frame#search_palette_recents[src=?]",
          "/#{one.external_id}/searches/recents"
      end
    end
  end

  private
    # Seed against the tenant user the signed-in identity actually resolves to:
    # tenant user IDs repeat across workspaces, so User.first is not it.
    def seed_search(workspace, identity, query)
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        user = User.find_by!(email_address: identity.email_address)
        Search.create!(user: user, query: query)
      end
    end
end
