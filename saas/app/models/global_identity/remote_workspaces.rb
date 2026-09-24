# frozen_string_literal: true

# The self-hosted workspaces a person keeps in their list, and the one order
# they share with sabha.co workspaces in the selector.
module GlobalIdentity::RemoteWorkspaces
  extend ActiveSupport::Concern

  MAX_REMOTE_WORKSPACES = 100

  class RemoteWorkspaceLimitReachedError < StandardError; end
  class RemoteWorkspaceClaimedError < StandardError; end

  included do
    has_many :remote_workspace_memberships, dependent: :destroy
    has_many :remote_workspace_pairings, dependent: :destroy
    # A pairing outlives whoever set it up, until the workspace pairs again
    has_many :paired_remote_workspaces, class_name: "RemoteWorkspace", foreign_key: :paired_by_id,
      inverse_of: :paired_by, dependent: :nullify
  end

  # Adds the workspace to the list, or brings a hidden entry back. The first
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

  # Starts pairing a workspace for "Continue with sabha.co". The secret waits
  # on the request until the workspace proves it's running with it.
  def pair_remote_workspace!(remote_workspace)
    raise RemoteWorkspaceClaimedError if Sso::ProviderClient.claims_host?(URI(remote_workspace.origin).host)

    remote_workspace = save_remote_workspace!(remote_workspace) if remote_workspace.new_record?

    transaction do
      # A new secret replaces the one still waiting, so only one ever works
      remote_workspace_pairings.where(remote_workspace: remote_workspace).delete_all
      remote_workspace_pairings.create!(remote_workspace: remote_workspace)
    end
  end

  # The person's entry for a workspace, including one they added under its
  # other address (the public address it reports, or the one that reports this)
  def remote_workspace_membership_for(remote_workspace)
    listed = remote_workspace_memberships.joins(:remote_workspace)
    listed.where(remote_workspaces: { origin: [ remote_workspace.origin, remote_workspace.alias_origin ].compact })
      .or(listed.where(remote_workspaces: { alias_origin: remote_workspace.origin }))
      .first
  end

  # Approving once lets sabha.co tell the workspace this person's name and
  # email from then on, and keeps the workspace in their list.
  def consent_to_remote_workspace!(remote_workspace)
    list_remote_workspace!(remote_workspace, source: :shortcut).update!(consented_at: Time.current)
  end

  def consented_to_remote_workspace?(remote_workspace)
    remote_workspace_memberships.consented.exists?(remote_workspace: remote_workspace)
  end

  # The owner of a Sabha Cloud droplet finds it in their list without adding it
  def list_sabha_cloud_workspace(remote_workspace)
    list_remote_workspace!(remote_workspace, source: :sabha_cloud)
  rescue RemoteWorkspaceLimitReachedError
    nil
  end

  # Signing in with the shortcut brings a hidden entry back
  def signed_in_to_remote_workspace!(remote_workspace)
    list_remote_workspace!(remote_workspace, source: :shortcut)
    remote_workspace.signed_in!
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

    in_switcher_order(workspaces + remotes)
  end

  # The same order for settings, which also shows hidden entries and
  # workspaces the person can no longer open
  def listed_memberships
    in_switcher_order(workspace_memberships_with_workspaces + remote_workspace_memberships.includes(:remote_workspace))
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
    def in_switcher_order(memberships)
      memberships.sort_by { [ it.position || Float::INFINITY, -it.updated_at.to_f ] }
    end

    # Two people adding a new origin at once both try to create its row; the
    # loser picks up the winner's.
    def save_remote_workspace!(remote_workspace)
      RemoteWorkspace.create_or_find_by!(origin: remote_workspace.origin) do |created|
        created.assign_attributes(remote_workspace.attributes.except("id", "origin", "created_at", "updated_at"))
      end
    end
end
