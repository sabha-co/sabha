class AddCounterCacheToRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :rooms, :messages_count, :integer, default: 0
    execute "update rooms set messages_count=(select count(*) from messages where room_id=rooms.id)"
  end
end
