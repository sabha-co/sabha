# Encrypts the few secrets kept in the database, such as the secret sabha.co
# shares with each workspace paired to it. The keys come from SECRET_KEY_BASE,
# so there are none to set or lose separately: changing it means every
# workspace has to pair again.
Rails.application.config.active_record.encryption.tap do |encryption|
  key_generator = Rails.application.key_generator

  encryption.primary_key = key_generator.generate_key("active_record_encryption.primary_key", 32).unpack1("H*")
  encryption.key_derivation_salt = key_generator.generate_key("active_record_encryption.key_derivation_salt", 32).unpack1("H*")
end
