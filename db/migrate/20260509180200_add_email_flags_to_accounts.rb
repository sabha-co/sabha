class AddEmailFlagsToAccounts < ActiveRecord::Migration[7.2]
  # Two account-level email feature flags (arch § 6.4). Real columns, not
  # account.settings JSON, because the dispatcher reads them per email candidate
  # and indexed boolean reads beat JSON extraction.
  def change
    add_column :accounts, :email_notifications_enabled, :boolean, default: false, null: false
    add_column :accounts, :weekly_digest_enabled,       :boolean, default: false, null: false
  end
end
