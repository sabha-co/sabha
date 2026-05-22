module User::SaasBridged
  extend ActiveSupport::Concern

  included do
    belongs_to :workspace_membership, optional: true, class_name: "WorkspaceMembership"

    after_update :sync_name_to_global_identity, if: -> { Sabha.saas? && saved_change_to_name? }
    after_update_commit :sync_workspace_membership_active, if: -> { Sabha.saas? && saved_change_to_status? }
  end

  def global_identity
    return nil unless Sabha.saas?
    workspace_membership&.global_identity
  end

  private
    # Mirror User#active? onto the untenanted WorkspaceMembership row so the
    # workspace selector can filter without cross-tenant queries. Runs post-
    # commit, so a Postgres failure here cannot roll back the SQLite write.
    # The auth-time guard reads the tenanted User row, so a stale mirror can
    # only hide a workspace the user should still see — repaired by the
    # workspace_membership:backfill_user_active rake task.
    def sync_workspace_membership_active
      workspace_membership&.update_column(:user_active, active?)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("Failed to mirror user_active for workspace_membership=#{workspace_membership_id}: #{e.message}")
    end

    def sync_name_to_global_identity
      global_identity&.update!(name: name)
    rescue => error
      Rails.logger.error "[GlobalIdentity sync] Failed to sync name for User##{id}: #{error.message}"
    end

    def close_remote_connections(reconnect: false)
      if Sabha.saas? && ApplicationRecord.current_tenant.present?
        ActionCable.server.remote_connections.where(
          current_tenant: ApplicationRecord.current_tenant,
          current_user: self
        ).disconnect reconnect: reconnect
      else
        ActionCable.server.remote_connections.where(current_user: self).disconnect reconnect: reconnect
      end
    end
end
