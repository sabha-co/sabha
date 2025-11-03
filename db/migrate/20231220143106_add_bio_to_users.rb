class AddBioToUsers < ActiveRecord::Migration[7.2]
  def change
    change_table :users do |t|
      t.text :bio
    end
  end
end
