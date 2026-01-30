class CleanupUnverifiedUsersJob < ApplicationJob
  def perform
    deleted_count = User.where(verified_at: nil)
                        .where(last_authenticated_at: nil)
                        .where(created_at: ...1.hour.ago)
                        .destroy_all
                        .count

    Rails.logger.info "[CleanupUnverifiedUsersJob] Deleted #{deleted_count} unverified users"
  end
end
