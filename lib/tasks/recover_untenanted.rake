# frozen_string_literal: true

desc "Recover untenanted PostgreSQL records from tenant SQLite databases"
task "recover:untenanted" => :environment do
  unless Sabha.saas?
    abort "SaaS mode is not enabled. Run with SAAS=true."
  end

  # Discover tenant directories on disk
  db_pattern = Rails.root.join("storage/workspaces/#{Rails.env}/*/db/main.sqlite3")
  tenant_ids = Dir.glob(db_pattern).map { |path| path.split("/")[-3] }.sort_by(&:to_i)

  if tenant_ids.empty?
    puts "No tenant databases found."
    exit
  end

  puts "Found #{tenant_ids.size} tenant database(s): #{tenant_ids.join(', ')}"
  puts

  recovered_workspaces = 0
  recovered_memberships = 0
  skipped_workspaces = 0

  tenant_ids.each do |tenant_id|
    unless ApplicationRecord.tenant_exist?(tenant_id)
      puts "  [SKIP] #{tenant_id} — tenant database not registered"
      next
    end

    existing_workspace = Workspace.find_by(external_id: tenant_id.to_i)
    if existing_workspace
      puts "  [OK] #{tenant_id} — workspace '#{existing_workspace.name}' already exists"
      skipped_workspaces += 1

      # Still recover missing memberships for existing workspaces
      ApplicationRecord.with_tenant(tenant_id) do
        recovered_memberships += recover_memberships(tenant_id)
      end
      next
    end

    # Read workspace data from tenant DB and create untenanted records
    ApplicationRecord.with_tenant(tenant_id) do
      account = Account.first
      unless account
        puts "  [SKIP] #{tenant_id} — no Account record found"
        next
      end

      users = User.unscoped.where(status: :active).order(:created_at)
      if users.empty?
        puts "  [SKIP] #{tenant_id} — no active users"
        next
      end

      # Find creator: first administrator, or first user
      creator_user = users.find(&:administrator?) || users.first
      creator_identity = find_or_create_identity(creator_user)

      # Create Workspace record
      workspace = Workspace.create!(
        external_id: tenant_id.to_i,
        name: account.name,
        creator: creator_identity
      )
      recovered_workspaces += 1

      puts "  [RECOVERED] #{tenant_id} — '#{workspace.name}' (creator: #{creator_identity.email_address})"

      # Create memberships for all active users
      recovered_memberships += recover_memberships(tenant_id)
    end
  rescue ActiveRecord::Tenanted::TenantDoesNotExistError
    puts "  [SKIP] #{tenant_id} — tenant database does not exist"
  rescue => e
    puts "  [ERROR] #{tenant_id} — #{e.class}: #{e.message}"
  end

  # Advance ExternalIdSequence past the highest tenant ID
  max_id = tenant_ids.map(&:to_i).max
  if max_id
    seq = Workspace::ExternalIdSequence.first_or_create!(value: max_id)
    if seq.value < max_id
      seq.update!(value: max_id)
      puts "\nAdvanced ExternalIdSequence to #{max_id}"
    else
      puts "\nExternalIdSequence already at #{seq.value} (>= #{max_id})"
    end
  end

  identities_count = GlobalIdentity.count
  memberships_count = WorkspaceMembership.count
  workspaces_count = Workspace.count

  puts
  puts "Recovery complete:"
  puts "  Workspaces recovered: #{recovered_workspaces}"
  puts "  Workspaces skipped (already existed): #{skipped_workspaces}"
  puts "  WorkspaceMemberships created: #{recovered_memberships}"
  puts
  puts "Current totals:"
  puts "  Workspaces: #{workspaces_count}"
  puts "  GlobalIdentities: #{identities_count}"
  puts "  WorkspaceMemberships: #{memberships_count}"
end

# Assumes caller is inside ApplicationRecord.with_tenant(tenant_id)
def recover_memberships(tenant_id)
  created = 0

  User.unscoped.where(status: :active).find_each do |user|
    identity = find_or_create_identity(user)

    membership = WorkspaceMembership.find_or_initialize_by(
      global_identity: identity,
      tenant: tenant_id.to_s
    )

    if membership.new_record?
      membership.save!
      membership.cache_user_id!(user.id)
      created += 1
    elsif membership.user_id != user.id
      membership.cache_user_id!(user.id)
    end
  end

  created
end

def find_or_create_identity(user)
  identity = GlobalIdentity.find_or_initialize_by(email_address: user.email_address)
  if identity.new_record?
    identity.name = user.name
    identity.verified_at = user.verified_at || Time.current
    identity.save!
  end
  identity
end
