# frozen_string_literal: true

require "zlib"

module WorkspaceSelectorHelper
  # Gradient pairs: [from_color, to_color] — rich, vibrant combinations
  WORKSPACE_GRADIENTS = [
    %w[#6B21A8 #A855F7], # Purple (like reference)
    %w[#1D4ED8 #60A5FA], # Blue
    %w[#047857 #34D399], # Emerald
    %w[#BE123C #FB7185], # Rose
    %w[#B45309 #FBBF24], # Amber
    %w[#3730A3 #818CF8], # Indigo
    %w[#0F766E #5EEAD4], # Teal
    %w[#C2410C #FB923C], # Orange
    %w[#0E7490 #67E8F9], # Cyan
    %w[#A21CAF #E879F9], # Fuchsia
    %w[#5B21B6 #C084FC], # Violet
    %w[#15803D #4ADE80] # Green
  ].freeze

  # Returns inline CSS style for a workspace's gradient background
  def workspace_gradient_style(workspace)
    from, to = WORKSPACE_GRADIENTS[Zlib.crc32(workspace.external_id.to_s) % WORKSPACE_GRADIENTS.size]
    "background: linear-gradient(135deg, #{from}, #{to});"
  end

  def show_workspace_selector?
    # Always show in SaaS mode when user is authenticated
    # Shows empty state on /workspaces/new when user has no workspaces
    Sabha.saas? && Current.global_identity.present?
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
