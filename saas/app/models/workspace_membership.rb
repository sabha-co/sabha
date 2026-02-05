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

  # Get the Account name for this workspace
  def account_name
    ApplicationRecord.with_tenant(tenant) do
      Account.first&.name
    end
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    nil
  end

  # Update the cached user_id
  def cache_user_id!(user_id)
    update_column(:user_id, user_id)
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
        # Use reactivate to restore room memberships, then update workspace_membership_id
        if user.deactivated?
          user.reactivate
          user.update!(workspace_membership_id: id) unless user.workspace_membership_id == id
        end
      else
        # Create new user
        user = User.create!(
          email_address: global_identity.email_address,
          workspace_membership_id: id,
          name: name || global_identity.email_address.split("@").first,
          role: role
        )
      end

      cache_user_id!(user.id) unless user_id == user.id
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
