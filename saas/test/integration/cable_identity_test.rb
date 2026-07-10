# frozen_string_literal: true

require_relative "../test_helper"

class CableIdentityTest < ActionDispatch::IntegrationTest
  # In SaaS the cable JWT must carry the tenant as its own plain-string
  # `current_tenant` claim — the gem's `around_command :with_tenant` opens the
  # tenant DB with it before the `current_user` GID is lazily resolved — and the
  # token must be bound to its workspace so it can't be replayed against another.
  setup do
    [ workspaces(:acme), workspaces(:shared) ].each do |workspace|
      tenant_id = workspace.external_id.to_s
      ApplicationRecord.create_tenant(tenant_id) unless ApplicationRecord.tenant_exist?(tenant_id)
    end
    sign_in_global_identity(global_identities(:alice))
  end

  test "the tenanted cable tag carries a JWT bound to the workspace tenant and user" do
    workspace = workspaces(:acme)
    workspace_get "/", workspace: workspace
    assert_response :success

    token = cable_jid(response.body)
    assert token.present?, "expected a jid identity param on the tenanted cable meta tag"

    ApplicationRecord.with_tenant(workspace.external_id.to_s) do
      decoded = AnyCable::JWT.decode(token)
      assert_equal workspace.external_id.to_s, decoded[:current_tenant],
        "tenant must ride as a plain-string claim, not only inside the user GID"
      assert decoded[:current_user].present?
      assert_equal workspace.external_id.to_s, decoded[:current_user].tenant,
        "the user GID must embed the workspace tenant"
    end
  end

  test "a token minted for one workspace cannot resolve its user in another tenant" do
    workspace_get "/", workspace: workspaces(:acme)
    token = cable_jid(response.body)

    ApplicationRecord.with_tenant(workspaces(:shared).external_id.to_s) do
      assert_raises(ActiveRecord::Tenanted::WrongTenantError) do
        AnyCable::JWT.decode(token)
      end
    end
  end

  test "the cable config endpoint returns the workspace url and a tenant-bound token" do
    workspace = workspaces(:acme)

    workspace_get "/api/cable", workspace: workspace

    assert_response :success
    body = JSON.parse(response.body)
    assert_includes body["url"], "wid=#{workspace.external_id}"

    ApplicationRecord.with_tenant(workspace.external_id.to_s) do
      decoded = AnyCable::JWT.decode(body["token"])
      assert_equal workspace.external_id.to_s, decoded[:current_tenant]
      assert_equal workspace.external_id.to_s, decoded[:current_user].tenant
    end
  end

  private
    def cable_jid(body)
      meta = body[/<meta name="action-cable-url"[^>]*>/]
      return unless meta
      CGI.unescapeHTML(meta)[/[?&]jid=([^"&]+)/, 1]
    end
end
