class DropLibraryTables < ActiveRecord::Migration[8.2]
  def change
    drop_table :library_watch_histories
    drop_table :library_sessions
    drop_table :library_classes_categories
    drop_table :library_categories
    drop_table :library_classes
  end
end
