class CreateNotificationBundles < ActiveRecord::Migration[7.2]
  # Per-user windows of accumulated missed-notification candidates.
  #
  # The partial unique index makes "at most one active bundle per user" a DB
  # invariant. Notification::Bundle.find_or_create_active_for relies on it for
  # race safety: simultaneous Message creates that both miss the find_by
  # cannot both insert — one raises ActiveRecord::RecordNotUnique and falls
  # through to the second read.
  def change
    create_table :notification_bundles do |t|
      t.references :user,         null: false, foreign_key: { on_delete: :cascade }
      t.string     :frequency,    null: false
      t.datetime   :starts_at,    null: false
      t.datetime   :ends_at,      null: false
      t.datetime   :delivered_at
      t.datetime   :canceled_at
      t.timestamps
    end

    add_index :notification_bundles, [ :user_id, :ends_at ],
              name: "index_notification_bundles_on_user_ends_at"

    add_index :notification_bundles, :user_id,
              name: "index_notification_bundles_active_per_user",
              unique: true,
              where: "delivered_at IS NULL AND canceled_at IS NULL"
  end
end
