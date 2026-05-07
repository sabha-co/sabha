# frozen_string_literal: true

class WorkspaceMembership < UntenantedRecord
  # Links GlobalIdentity to a workspace (tenant)
  #
  # This is the cross-database link between:
  # - GlobalIdentity (untenanted DB)
  # - User (tenanted workspace DB)
  #
  # The `tenant` column stores the workspace's external_id as a string.
  # The `user_id` column caches the User's ID for faster lookups.
  # The `position` column controls display order in the workspace selector.

  belongs_to :global_identity, touch: true
  belongs_to :workspace, primary_key: :external_id, foreign_key: :tenant, optional: true

  validates :tenant, presence: true
  validates :global_identity_id, uniqueness: { scope: :tenant, message: "is already a member of this workspace" }

  # Order by position (user-defined), falling back to most recently updated
  scope :ordered, -> { order(Arel.sql("COALESCE(position, 999999) ASC, updated_at DESC")) }

  scope :for_workspace, ->(workspace) {
    where(tenant: workspace.external_id.to_s)
      .joins(:global_identity)
      .joins("LEFT JOIN (#{GlobalSession.select("global_identity_id, MAX(last_active_at) AS last_active_at").group(:global_identity_id).to_sql}) last_sessions ON last_sessions.global_identity_id = workspace_memberships.global_identity_id")
      .includes(:global_identity)
      .select("workspace_memberships.*, last_sessions.last_active_at AS last_active_at")
  }

  scope :by_last_active, -> { order("last_sessions.last_active_at DESC NULLS LAST") }

  scope :search, ->(query) {
    if query.present?
      where("global_identities.email_address ILIKE :q OR global_identities.name ILIKE :q", q: "%#{sanitize_sql_like(query)}%")
    else
      all
    end
  }

  # Bulk update positions for a global identity's workspace memberships
  def self.reorder_for_identity(global_identity, workspace_ids)
    return false if workspace_ids.blank? || !workspace_ids.is_a?(Array)

    transaction do
      workspace_ids.each_with_index do |external_id, index|
        global_identity.workspace_memberships
          .where(tenant: external_id.to_s)
          .update_all(position: index, updated_at: Time.current)
      end
    end
    true
  end

  # Get the User record from the tenanted database
  # Returns nil if user doesn't exist yet (created lazily on first visit)
  def user
    return nil if user_id.blank?

    ApplicationRecord.with_tenant(tenant) do
      User.find_by(id: user_id)
    end
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    nil
  end

  # Mirror of the per-workspace User's :active status. Source of truth lives on
  # the tenanted User row; the `user_active` column is a denormalized cache
  # updated by User#revoke_access / User#unban / User#reactivate so the workspace
  # selector can filter without cross-tenant queries (activerecord-tenanted
  # prohibits shard swapping inside an active tenant context). NOTE: this is
  # NOT the Deactivatable soft-delete pattern — the membership row is preserved
  # for staff visibility (Admin::WorkspaceMembersController etc.) regardless of
  # this flag.
  scope :user_active, -> { where(user_active: true) }

  # Get the Account name for this workspace
  def account_name
    ApplicationRecord.with_tenant(tenant) do
      Account.first&.name
    end
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    nil
  end

  # Update the cached user_id and reset the user_active mirror. Linking a new
  # User to a membership implies the user is active — necessary for the rejoin
  # path after a hard destroy, which left user_active=false on the orphan row.
  def cache_user_id!(user_id)
    update_columns(user_id: user_id, user_active: true)
  end

  # True when the per-workspace User has been banned or deactivated. Mirrors
  # User#active?'s inverse via the user_active cache column — see scope above.
  def inactive?
    !user_active
  end

  # Create or find the User record in the workspace database
  # Uses find_or_create pattern to be idempotent
  # Reactivates deactivated users on rejoin
  def create_user!(name: nil, role: :member)
    ApplicationRecord.with_tenant(tenant) do
      # Look for existing user (including deactivated ones)
      user = User.unscoped.find_by(email_address: global_identity.email_address)

      if user
        # Reactivate if deactivated (rejoining after leaving)
        # Use reactivate to restore room memberships, then update workspace_membership_id and role
        if user.deactivated?
          user.reactivate
          user.update!(workspace_membership_id: id, role: role)
        end
      else
        # Create new user
        user = User.create!(
          email_address: global_identity.email_address,
          workspace_membership_id: id,
          name: name || global_identity.name || global_identity.email_address.split("@").first.titleize,
          role: role,
          verified_at: global_identity.verified? ? Time.current : nil
        )
      end

      cache_user_id!(user.id) unless user_id == user.id
      Current.user = user if Current.workspace_membership == self
      user
    end
  end

  # Leave workspace - deactivates User, destroys membership
  # Raises LastAdministratorError if user is the last admin
  def leave!
    raise LastAdministratorError if workspace&.last_administrator?(user)

    transaction do
      # Deactivate User in tenanted DB (soft delete, messages remain)
      ApplicationRecord.with_tenant(tenant) do
        User.find_by(id: user_id)&.deactivate if user_id.present?
      end
      destroy!
    end
  end
end
