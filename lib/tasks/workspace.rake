# frozen_string_literal: true

namespace :workspace do
  desc "List all workspaces"
  task list: :environment do
    unless Campfire.saas?
      puts "SaaS mode is not enabled. Run with SAAS=true or bin/rails saas:enable"
      exit 1
    end

    workspaces = Workspace.all.order(:external_id)

    if workspaces.empty?
      puts "No workspaces found."
    else
      puts "Workspaces:"
      puts "-" * 60
      workspaces.each do |workspace|
        status = workspace.suspended? ? " [SUSPENDED]" : ""
        puts "  #{workspace.external_id}: #{workspace.name}#{status}"
      end
      puts "-" * 60
      puts "Total: #{workspaces.count} workspace(s)"
    end
  end

  desc "Create a new workspace"
  task :create, [ :name, :email ] => :environment do |_t, args|
    unless Campfire.saas?
      puts "SaaS mode is not enabled. Run with SAAS=true or bin/rails saas:enable"
      exit 1
    end

    name = args[:name]
    email = args[:email]

    if name.blank?
      puts "Usage: bin/rails workspace:create[name,email]"
      puts "  name  - Workspace name (required)"
      puts "  email - Creator's email (required)"
      exit 1
    end

    if email.blank?
      puts "Email is required to create a workspace"
      exit 1
    end

    creator = GlobalIdentity.find_or_create_by!(email_address: email.downcase)
    creator.verify! unless creator.verified?

    workspace = Workspace.create_with_database!(name: name, creator: creator)

    puts "Workspace created successfully!"
    puts "  ID: #{workspace.external_id}"
    puts "  Name: #{workspace.name}"
    puts "  URL: /#{workspace.external_id}/"
    puts "  Creator: #{creator.email_address}"
  end

  desc "Destroy a workspace and its database"
  task :destroy, [ :external_id ] => :environment do |_t, args|
    unless Campfire.saas?
      puts "SaaS mode is not enabled. Run with SAAS=true or bin/rails saas:enable"
      exit 1
    end

    external_id = args[:external_id]

    if external_id.blank?
      puts "Usage: bin/rails workspace:destroy[external_id]"
      exit 1
    end

    workspace = Workspace.find_by(external_id: external_id)

    if workspace.nil?
      puts "Workspace #{external_id} not found"
      exit 1
    end

    print "Are you sure you want to destroy workspace '#{workspace.name}' (#{external_id})? [y/N] "
    confirm = $stdin.gets.chomp.downcase

    unless confirm == "y"
      puts "Aborted."
      exit 0
    end

    # Destroy tenant database
    ApplicationRecord.destroy_tenant(external_id.to_s)

    # Destroy workspace record
    workspace.destroy!

    puts "Workspace #{external_id} destroyed."
  end

  desc "Show workspace info"
  task :info, [ :external_id ] => :environment do |_t, args|
    unless Campfire.saas?
      puts "SaaS mode is not enabled. Run with SAAS=true or bin/rails saas:enable"
      exit 1
    end

    external_id = args[:external_id] || ApplicationRecord.current_tenant

    if external_id.blank?
      puts "Usage: bin/rails workspace:info[external_id]"
      puts "  Or set ARTENANT environment variable"
      exit 1
    end

    workspace = Workspace.find_by(external_id: external_id)

    if workspace.nil?
      puts "Workspace #{external_id} not found"
      exit 1
    end

    puts "Workspace Info"
    puts "-" * 40
    puts "  ID: #{workspace.external_id}"
    puts "  Name: #{workspace.name}"
    puts "  Slug: #{workspace.slug || '(none)'}"
    puts "  Creator: #{workspace.creator.email_address}"
    puts "  Created: #{workspace.created_at}"
    puts "  Status: #{workspace.suspended? ? 'SUSPENDED' : 'Active'}"
    puts "  Members: #{workspace.workspace_memberships.count}"

    ApplicationRecord.with_tenant(external_id.to_s) do
      puts "  Users: #{User.count}"
      puts "  Rooms: #{Room.count}"
      puts "  Messages: #{Message.count}"
    end
  end
end
