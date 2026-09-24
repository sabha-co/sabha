json.protocol_major Sabha::PROTOCOL_MAJOR
json.product do
  json.name Branding.app_name
  json.short_name Branding.app_short_name
  json.slug Branding.app_short_name.to_s.parameterize.presence || "sabha"
end
json.sign_in_path sign_in_entry_path
json.destinations_path api_destinations_path

# A self-hosted install is one community, so it can say which one. sabha.co
# hosts many, so it has no single community to describe, and says so: it
# can't be added to anyone's list of communities, whatever address reaches it.
json.multi_tenant true if Sabha.saas?

if !Sabha.saas? && (account = Current.account)
  json.community do
    json.name account.name
    json.logo_url(account.logo.attached? ? fresh_account_logo_url(size: "small") : nil)
    json.url Branding.app_url
  end
end

# Proves to sabha.co, while it pairs with this server, that the server holds
# the secret it was given and answers at this origin. The signed text can't be
# mistaken for a sign-in payload, which is base64 and never contains a colon.
if (hub = Sso::Provider.hub).configured?
  json.hub_proof hub.pairing_proof(request.base_url)
end
