class DropLiveEvents < ActiveRecord::Migration[8.2]
  def change
    drop_table :live_events
  end
end
