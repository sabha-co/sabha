class AddPinnedMessageToRooms < ActiveRecord::Migration[8.2]
  def change
    # A room's single pinned message (nullable → zero-or-one pin per room). The
    # FK nullifies on the message's deletion so a pin can't dangle.
    add_reference :rooms, :pinned_message, null: true,
      foreign_key: { to_table: :messages, on_delete: :nullify }
  end
end
