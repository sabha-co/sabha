# frozen_string_literal: true

module WorkspaceSelectorHelper
  def show_workspace_selector?
    # Always show in SaaS mode when user is authenticated
    # Shows empty state on /workspaces/new when user has no workspaces
    Campfire.saas? && Current.global_identity.present?
  end

  def workspace_selector_workspaces
    return [] unless Current.global_identity

    Current.global_identity.workspace_memberships_ordered.filter_map(&:workspace).select(&:active?)
  end

  def workspace_url(workspace)
    root_path(script_name: workspace.slug)
  end

  def workspace_logo_url(workspace)
    account_logo_path(script_name: workspace.slug, size: "small")
  end
end
