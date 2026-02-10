class MakeMembersHashUniqueOnRooms < ActiveRecord::Migration[8.2]
  def change
    remove_index :rooms, :members_hash
    add_index :rooms, :members_hash, unique: true
  end
end
