json.protocol_major Sabha::PROTOCOL_MAJOR
json.product do
  json.name Branding.app_name
  json.short_name Branding.app_short_name
  json.slug Branding.app_short_name.to_s.parameterize.presence || "sabha"
end
json.sign_in_path sign_in_entry_path
json.destinations_path api_destinations_path
