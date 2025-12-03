class ChangeActiveToStatusOnUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :status, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        # Migrate existing data:
        # - active=false -> status=1 (deactivated)
        # - suspended_at IS NOT NULL -> status=2 (banned)
        execute "UPDATE users SET status = 1 WHERE active = 0"
        execute "UPDATE users SET status = 2 WHERE suspended_at IS NOT NULL"
      end
    end

    remove_column :users, :active, :boolean
    remove_column :users, :suspended_at, :datetime
  end
end
