# frozen_string_literal: true

# The self-hosted communities a person keeps in their list, and the one order
# they share with sabha.co workspaces in the selector.
module GlobalIdentity::RemoteWorkspaces
  extend ActiveSupport::Concern

  MAX_REMOTE_WORKSPACES = 100

  class RemoteWorkspaceLimitReachedError < StandardError; end

  included do
    has_many :remote_workspace_memberships, dependent: :destroy
  end

  # Adds the community to the list, or brings a hidden entry back. The first
  # person to list an origin creates its shared row from the manifest.
  def list_remote_workspace!(remote_workspace, source:)
    remote_workspace = save_remote_workspace!(remote_workspace) if remote_workspace.new_record?

    with_lock do
      membership = remote_workspace_memberships.find_or_initialize_by(remote_workspace: remote_workspace)
      raise RemoteWorkspaceLimitReachedError if membership.new_record? && remote_workspace_limit_reached?

      membership.source ||= source
      membership.update!(hidden: false)
      membership
    end
  end

  def remote_workspace_limit_reached?
    remote_workspace_memberships.count >= MAX_REMOTE_WORKSPACES
  end

  # Workspaces and list entries in the person's own order. Entries without a
  # position (never reordered) follow, most recently touched first, which is
  # how the selector has always ordered workspaces.
  def switcher_memberships
    workspaces = workspace_memberships.user_active.includes(:workspace).select { it.workspace&.active? }
    remotes = remote_workspace_memberships.visible.includes(:remote_workspace)

    (workspaces + remotes).sort_by { [ it.position || Float::INFINITY, -it.updated_at.to_f ] }
  end

  # Positions come from the selector as workspace external ids and
  # "remote:<membership id>", in their new order.
  def reorder_switcher(ids)
    return false unless ids.is_a?(Array) && ids.any?

    transaction do
      ids.each_with_index do |id, position|
        if (membership_id = id.to_s[/\Aremote:(\d+)\z/, 1])
          remote_workspace_memberships.where(id: membership_id).update_all(position: position, updated_at: Time.current)
        else
          workspace_memberships.where(tenant: id.to_s.delete_prefix("workspace:")).update_all(position: position, updated_at: Time.current)
        end
      end
    end
    true
  end

  private
    # Two people adding a new origin at once both try to create its row; the
    # loser picks up the winner's.
    def save_remote_workspace!(remote_workspace)
      RemoteWorkspace.create_or_find_by!(origin: remote_workspace.origin) do |created|
        created.assign_attributes(remote_workspace.attributes.except("id", "origin", "created_at", "updated_at"))
      end
    end
end
