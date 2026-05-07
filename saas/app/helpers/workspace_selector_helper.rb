# frozen_string_literal: true

require "zlib"

module WorkspaceSelectorHelper
  # Gradient pairs: [from_color, to_color] — rich, vibrant combinations (OKLch)
  WORKSPACE_GRADIENTS = [
    [ "oklch(40% 0.17 310)", "oklch(65% 0.20 300)" ], # Purple
    [ "oklch(45% 0.20 260)", "oklch(68% 0.14 250)" ], # Blue
    [ "oklch(48% 0.15 165)", "oklch(75% 0.17 165)" ], # Emerald
    [ "oklch(45% 0.22 15)",  "oklch(70% 0.16 10)" ],  # Rose
    [ "oklch(50% 0.15 60)",  "oklch(80% 0.16 80)" ],  # Amber
    [ "oklch(38% 0.18 275)", "oklch(65% 0.15 270)" ], # Indigo
    [ "oklch(48% 0.12 185)", "oklch(82% 0.14 180)" ], # Teal
    [ "oklch(50% 0.18 40)",  "oklch(75% 0.16 45)" ],  # Orange
    [ "oklch(48% 0.10 220)", "oklch(82% 0.12 210)" ], # Cyan
    [ "oklch(48% 0.22 320)", "oklch(75% 0.20 325)" ], # Fuchsia
    [ "oklch(38% 0.18 290)", "oklch(68% 0.16 295)" ], # Violet
    [ "oklch(45% 0.17 145)", "oklch(72% 0.20 150)" ] # Green
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

    Current.global_identity.workspace_memberships_ordered.user_active
      .filter_map { |m| m.workspace if m.workspace&.active? }
  end

  def workspace_url(workspace)
    root_path(script_name: workspace.slug)
  end

  def workspace_logo_url(workspace)
    account_logo_path(script_name: workspace.slug, size: "small")
  end
end
