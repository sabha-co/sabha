class CleanupUnverifiedUsersJob < ApplicationJob
  def perform
    if Sabha.saas?
      ApplicationRecord.with_each_tenant do
        cleanup_unverified_users
      end
    else
      cleanup_unverified_users
    end
  end

  private

  def cleanup_unverified_users
    deleted_count = User.where(verified_at: nil)
                        .where(last_authenticated_at: nil)
                        .where(created_at: ...1.hour.ago)
                        .destroy_all
                        .count

    Rails.logger.info "[CleanupUnverifiedUsersJob] Deleted #{deleted_count} unverified users"
  end
end
