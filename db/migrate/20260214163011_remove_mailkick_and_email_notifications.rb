class RemoveMailkickAndEmailNotifications < ActiveRecord::Migration[8.2]
  def up
    drop_table :mailkick_subscriptions if table_exists?(:mailkick_subscriptions)
    remove_column :memberships, :notified_until if column_exists?(:memberships, :notified_until)
  end

  def down
    unless table_exists?(:mailkick_subscriptions)
      create_table :mailkick_subscriptions do |t|
        t.string :subscriber_type
        t.integer :subscriber_id
        t.string :list
        t.timestamps
        t.index [:subscriber_type, :subscriber_id, :list], unique: true, name: "index_mailkick_subscriptions_on_subscriber_and_list"
      end
    end

    unless column_exists?(:memberships, :notified_until)
      add_column :memberships, :notified_until, :datetime
    end
  end
end
