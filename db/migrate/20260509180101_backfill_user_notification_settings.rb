class BackfillUserNotificationSettings < ActiveRecord::Migration[7.2]
  # Idempotent backfill so the deploy migration is safe to rerun, and so the
  # SaaS per-tenant runner (with_temporary_connection) doesn't need to
  # instantiate AR models — see migration 20260426133120 for the same
  # SaaS-friendly raw-SQL pattern.
  #
  # Defaults: missed email off, push on, mode mentions_and_dms, frequency
  # hourly, weekly digest subscribed (admin-enabled with member opt-out).
  def up
    execute <<~SQL.squish
      INSERT INTO user_notification_settings
        (user_id, mode, missed_email_enabled, email_frequency, weekly_digest_subscribed, push_enabled, created_at, updated_at)
      SELECT users.id, 'mentions_and_dms', #{quoted_false}, 'hourly', #{quoted_true}, #{quoted_true}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM users
      WHERE NOT EXISTS (
        SELECT 1 FROM user_notification_settings
        WHERE user_notification_settings.user_id = users.id
      )
    SQL
  end

  def down
    # Backfill is additive; no destructive down action.
  end

  private
    def quoted_true
      connection.quoted_true
    end

    def quoted_false
      connection.quoted_false
    end
end
