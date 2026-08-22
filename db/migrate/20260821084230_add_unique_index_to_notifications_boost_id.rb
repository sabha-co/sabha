class AddUniqueIndexToNotificationsBoostId < ActiveRecord::Migration[8.2]
  def up
    dedupe_boost_notifications

    # Swap the plain lookup index for a unique one so a boost can never
    # accumulate more than one notification (a boost notifies its message's
    # creator exactly once). Partial on boost_id — the mention/thread_reply
    # rows that leave it NULL keep their own unique index. Guarded so a drifted
    # tenant DB can't abort the fleet migrate.
    remove_index :notifications, name: "index_notifications_on_boost_id" if index_exists?(:notifications, :boost_id, name: "index_notifications_on_boost_id")
    unless index_exists?(:notifications, :boost_id, name: "index_notifications_on_boost_id", unique: true)
      add_index :notifications, :boost_id, unique: true,
        where: "boost_id IS NOT NULL", name: "index_notifications_on_boost_id"
    end
  end

  def down
    remove_index :notifications, name: "index_notifications_on_boost_id"
    add_index :notifications, :boost_id,
      where: "boost_id IS NOT NULL", name: "index_notifications_on_boost_id"
  end

  private
    # Racing dispatch jobs could insert several rows for one boost. Keep the
    # earliest per boost and drop the rest so the unique index can build. Runs on
    # the migration's own connection via raw SQL — referencing the Notification
    # model would resolve its (tenanted) connection and blow up mid-migration.
    def dedupe_boost_notifications
      execute(<<~SQL.squish)
        DELETE FROM notifications
        WHERE boost_id IS NOT NULL
          AND id NOT IN (
            SELECT MIN(id) FROM notifications
            WHERE boost_id IS NOT NULL
            GROUP BY boost_id
          )
      SQL
    end
end
