class AddAcceptedTermsAtToGlobalIdentities < ActiveRecord::Migration[8.2]
  def change
    add_column :global_identities, :accepted_terms_at, :datetime
  end
end
