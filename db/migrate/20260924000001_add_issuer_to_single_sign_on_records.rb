class AddIssuerToSingleSignOnRecords < ActiveRecord::Migration[8.2]
  # Sign-in links used to come from one provider. They're now keyed by the
  # provider's origin, so a member can sign in through the community's own
  # single sign-on and through sabha.co. Existing rows belong to the custom
  # provider; rows left blank here (no SSO_PROVIDER_URL at migrate time) are
  # stamped by that provider's next callback.
  def up
    add_column :single_sign_on_records, :issuer, :string

    remove_index :single_sign_on_records, :external_id
    remove_index :single_sign_on_records, :user_id
    add_index :single_sign_on_records, [ :issuer, :external_id ], unique: true
    add_index :single_sign_on_records, [ :issuer, :user_id ], unique: true
    add_index :single_sign_on_records, :user_id

    if (issuer = custom_issuer)
      execute "UPDATE single_sign_on_records SET issuer = #{connection.quote(issuer)}"
    end
  end

  def down
    remove_index :single_sign_on_records, :user_id
    remove_index :single_sign_on_records, [ :issuer, :user_id ]
    remove_index :single_sign_on_records, [ :issuer, :external_id ]
    add_index :single_sign_on_records, :external_id, unique: true
    add_index :single_sign_on_records, :user_id, unique: true
    remove_column :single_sign_on_records, :issuer
  end

  private
    def custom_issuer
      uri = URI.parse(ENV["SSO_PROVIDER_URL"].to_s)
      "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}".downcase if uri.is_a?(URI::HTTP) && uri.host
    rescue URI::InvalidURIError
      nil
    end
end
