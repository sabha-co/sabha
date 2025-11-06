class AddActiveToBookmarks < ActiveRecord::Migration[7.2]
  def change
    add_column :bookmarks, :active, :boolean, default: true
  end
end
