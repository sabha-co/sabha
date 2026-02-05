# frozen_string_literal: true

class AddUnconfirmedEmailToGlobalIdentities < ActiveRecord::Migration[8.2]
  def change
    add_column :global_identities, :unconfirmed_email, :string
  end
end
