class CreateUserNotificationSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :user_notification_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :mode, null: false, default: "mentions_and_dms"
      t.boolean :missed_email_enabled, null: false, default: false
      t.string :email_frequency, null: false, default: "hourly"
      t.boolean :weekly_digest_subscribed, null: false, default: true
      t.boolean :push_enabled, null: false, default: true
      t.datetime :last_digest_sent_at
      t.timestamps
    end
  end
end
