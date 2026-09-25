# frozen_string_literal: true

require_relative "../../test_helper"

module Saas
  class SettingsControllerTest < ActionDispatch::IntegrationTest
    test "show requires authentication" do
      get settings_path
      assert_redirected_to new_session_path
    end

    test "show renders form when authenticated" do
      sign_in_global_identity(global_identities(:alice))
      get settings_path
      assert_response :success
    end

    test "show displays workspaces list" do
      sign_in_global_identity(global_identities(:alice))
      get settings_path
      assert_response :success
      assert_select "h2", /Your Workspaces/i
      # Alice belongs to Acme Corp and Shared Workspace; both must render as rows
      assert_select "strong", text: "Acme Corp"
      assert_select "strong", text: "Shared Workspace"
    end

    test "show lists self-hosted workspaces in the same list as sabha.co ones, in the selector's order" do
      bob = global_identities(:bob)
      sign_in_global_identity(bob)
      club = remote_workspace_memberships(:bob_club)
      club.update!(hidden: true)
      bob.reorder_selector([ "remote:#{club.id}", "1000002", "remote:#{remote_workspace_memberships(:bob_acme).id}", "1000003" ])

      get settings_path

      assert_equal [ "Club", "Widgets Inc", "Acme", "Shared Workspace" ], css_select(".panel:first-of-type strong").map(&:text)
      assert_select "span", "Self-hosted · chat.acme.org"
      assert_select ".list-tag--negative", "Unreachable"
      assert_select ".list-tag", "Hidden"
      assert_select "button", "Show in sidebar"
      assert_select "a[href=?]", new_remote_workspace_path, text: /Add a self-hosted workspace/
    end

    test "the workspace list can be reordered in place, for the desktop app that hides the selector" do
      bob = global_identities(:bob)
      sign_in_global_identity(bob)
      club = remote_workspace_memberships(:bob_club)
      acme = remote_workspace_memberships(:bob_acme)
      bob.reorder_selector([ "remote:#{club.id}", "1000002", "remote:#{acme.id}", "1000003" ])

      get settings_path

      assert_select ".saas-settings [data-controller~=workspace-sortable]"
      assert_equal [ "remote:#{club.id}", "1000002", "remote:#{acme.id}", "1000003" ],
        css_select(".saas-settings [data-workspace-sortable-target=item]").map { it["data-workspace-id"] }
      assert_select ".saas-settings [data-workspace-sortable-target=item][draggable=true]", 4
      assert_select ".saas-settings p", "Drag to change the order."
    end

    test "the selector lists self-hosted workspaces beside sabha.co ones, linking to their own sites" do
      sign_in_global_identity(global_identities(:bob))

      get settings_path

      assert_select ".workspace-selector a[href='https://chat.acme.org'][data-workspace-id^='remote:']"
      assert_select ".workspace-selector a.workspace-selector__item--unreachable[href='https://club.example']"
      assert_select ".workspace-selector a[href='https://chat.acme.org'] img[src=?]", "/remote_workspaces/#{remote_workspaces(:acme).id}/logo"
    end

    test "self-hosted workspaces open in a new tab, so this one keeps the selector" do
      sign_in_global_identity(global_identities(:bob))

      get settings_path

      assert_select ".workspace-selector a[href='https://chat.acme.org'][target=_blank][rel=noopener]"
      assert_select ".workspace-selector a[data-workspace-id]:not([data-workspace-id^='remote:'])[target]", count: 0
    end

    test "self-hosted workspaces carry a server badge in the selector, sabha.co ones don't" do
      sign_in_global_identity(global_identities(:bob))

      get settings_path

      assert_select ".workspace-selector a[href='https://chat.acme.org'] .workspace-selector__self-hosted[aria-hidden=true] .icon--server"
      assert_select ".workspace-selector a[data-workspace-id]:not([data-workspace-id^='remote:']) .workspace-selector__self-hosted", count: 0
    end

    test "the selector's add button offers a new workspace or a self-hosted workspace" do
      sign_in_global_identity(global_identities(:alice))

      get settings_path

      assert_select ".workspace-selector details summary.workspace-selector__add"
      assert_select ".workspace-selector__add-options a[href=?]", new_workspace_path, text: "Create a workspace"
      assert_select ".workspace-selector__add-options a[href=?]", new_remote_workspace_path, text: "Add a self-hosted workspace"
    end

    test "update requires authentication" do
      patch settings_path, params: { global_identity: { email_address: "new@example.com" } }
      assert_redirected_to new_session_path
    end

    test "update with same email redirects with no changes" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: identity.email_address } }
      assert_redirected_to settings_path
      assert_equal "No changes made", flash[:notice]
    end

    test "update with taken email shows error" do
      identity = global_identities(:alice)
      other = global_identities(:bob)
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: other.email_address } }
      assert_response :unprocessable_entity
    end

    test "update with new email stores pending email and sends verification code" do
      identity = global_identities(:alice)
      original_email = identity.email_address
      sign_in_global_identity(identity)
      new_email = "newemail@example.com"

      assert_difference "AuthCode.count", 1 do
        assert_enqueued_emails 1 do
          patch settings_path, params: { global_identity: { email_address: new_email } }
        end
      end

      # User stays signed in and redirects to auth code entry
      assert_redirected_to auth_code_path
      assert_match /Enter the verification code/, flash[:notice]

      # Email NOT changed yet - stored as pending
      identity.reload
      assert_equal original_email, identity.email_address
      assert_equal new_email, identity.unconfirmed_email
      assert identity.verified_at.present?, "Should remain verified"

      # Auth code has email_change purpose
      auth_code = AuthCode.last
      assert auth_code.email_change?
    end

    test "update with same email cancels pending email change" do
      identity = global_identities(:alice)
      identity.update!(unconfirmed_email: "alice-pending-change@example.com")
      sign_in_global_identity(identity)

      patch settings_path, params: { global_identity: { email_address: identity.email_address } }
      assert_redirected_to settings_path

      identity.reload
      assert_nil identity.unconfirmed_email
    end

    test "update with blank email shows error" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)

      assert_no_difference "AuthCode.count" do
        patch settings_path, params: { global_identity: { email_address: "" } }
      end

      assert_response :unprocessable_entity
    end

    test "update sends verification code to the new email address" do
      identity = global_identities(:alice)
      sign_in_global_identity(identity)
      new_email = "newemail@example.com"

      patch settings_path, params: { global_identity: { email_address: new_email } }

      # Verify the email is sent to the NEW address, not the old one
      auth_code = AuthCode.last
      mail = AuthCodeMailer.code(auth_code)
      assert_equal [ new_email ], mail.to
      assert_not_equal [ identity.email_address ], mail.to
    end
  end
end
