# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class RemoteWorkspaceListsControllerTest < ActionDispatch::IntegrationTest
    test "clears only the person's own list" do
      sign_in_global_identity(global_identities(:bob))

      delete "/remote_workspace_list"

      assert_redirected_to settings_path
      assert_empty global_identities(:bob).remote_workspace_memberships
      assert_equal 1, global_identities(:alice).remote_workspace_memberships.count
    end
  end
end
