class AddUniqueIndexToNotificationsBoostId < ActiveRecord::Migration[8.2]
  def up
    dedupe_boost_notifications

    # Swap the plain lookup index for a unique one so a boost can never
    # accumulate more than one notification (a boost notifies its message's
    # creator exactly once). Partial on boost_id — the mention/thread_reply
    # rows that leave it NULL keep their own unique index.
    remove_index :notifications, name: "index_notifications_on_boost_id"
    add_index :notifications, :boost_id, unique: true,
      where: "boost_id IS NOT NULL", name: "index_notifications_on_boost_id"
  end

  def down
    remove_index :notifications, name: "index_notifications_on_boost_id"
    add_index :notifications, :boost_id,
      where: "boost_id IS NOT NULL", name: "index_notifications_on_boost_id"
  end

  private
    # Racing dispatch jobs could insert several rows for one boost. Keep the
    # earliest per boost and drop the rest so the unique index can build.
    def dedupe_boost_notifications
      keeper_ids = Notification.where.not(boost_id: nil).group(:boost_id).minimum(:id).values
      return if keeper_ids.empty?

      Notification.where.not(boost_id: nil).where.not(id: keeper_ids).delete_all
    end
end
