class CreateNotificationBundleItems < ActiveRecord::Migration[7.2]
  # Items appended to a bundle as eligible mention/DM messages occur.
  #
  # `kind` is a separate vocabulary from Notification.activity_type — bundle
  # items track email-routing reasons ("mention" / "direct_message") which do
  # not map 1:1 to the persisted activity_type enum (there is no
  # `direct_message` Notification row). Sharing the column name across two
  # non-equal vocabularies would breed bugs, so it stays distinct.
  #
  # The (bundle_id, message_id, kind) unique index handles within-bundle
  # dedup so the dispatcher can call insert_all with unique_by: ... safely.
  def change
    create_table :notification_bundle_items do |t|
      t.references :bundle,  null: false, foreign_key: { to_table: :notification_bundles }
      t.references :message, null: false, foreign_key: true
      t.references :actor,   null: false, foreign_key: { to_table: :users }
      t.string     :kind,    null: false
      t.timestamps
    end

    add_index :notification_bundle_items, [ :bundle_id, :message_id, :kind ],
              name: "index_notification_bundle_items_unique_per_bundle",
              unique: true
  end
end
