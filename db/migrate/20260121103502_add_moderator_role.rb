class AddModeratorRole < ActiveRecord::Migration[8.2]
  def up
    # Current: member=0, administrator=1, bot=2
    # Target:  member=0, moderator=1, administrator=2, bot=3
    execute "UPDATE users SET role = 3 WHERE role = 2" # bot -> 3
    execute "UPDATE users SET role = 2 WHERE role = 1" # administrator -> 2
    # moderator=1 is now available for new assignments
  end

  def down
    # Revert: demote all moderators to members, shift admin and bot back
    execute "UPDATE users SET role = 0 WHERE role = 1" # moderator -> member
    execute "UPDATE users SET role = 1 WHERE role = 2" # administrator -> 1
    execute "UPDATE users SET role = 2 WHERE role = 3" # bot -> 2
  end
end
