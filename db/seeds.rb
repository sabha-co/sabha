if Sabha.saas?
  email = ENV.fetch("ADMIN_EMAIL", "admin@example.com").presence || "admin@example.com"
  name  = ENV.fetch("WORKSPACE_NAME", "Sabha")

  # Idempotent: skip if default workspace already exists
  if Workspace.exists?(external_id: 1000001)
    puts "Default workspace already exists (ID: 1000001), skipping."
  else
    creator = GlobalIdentity.find_or_create_by!(email_address: email.downcase)
    creator.verify! unless creator.verified?

    workspace = Workspace.create_with_database!(name: name, creator: creator)

    puts "Workspace created: #{workspace.name} (ID: #{workspace.external_id})"
    puts "Admin: #{creator.email_address}"
  end
end
