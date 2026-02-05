# frozen_string_literal: true

namespace :saas do
  SAAS_MARKER = File.expand_path("../../tmp/saas.txt", __dir__)

  desc "Enable SaaS mode (multi-tenancy)"
  task :enable do
    FileUtils.mkdir_p(File.dirname(SAAS_MARKER))
    FileUtils.touch(SAAS_MARKER)
    puts "SaaS mode enabled (#{SAAS_MARKER} created)"
    puts "Run 'bundle install' to load Gemfile.saas, then 'bin/rails saas:setup'"
  end

  desc "Disable SaaS mode (single-tenant)"
  task :disable do
    FileUtils.rm_f(SAAS_MARKER)
    puts "SaaS mode disabled (#{SAAS_MARKER} removed)"
    puts "Run 'bundle install' to use standard Gemfile"
  end

  desc "Check SaaS mode status"
  task :status do
    require_relative "../../lib/campfire"

    if Campfire.saas?
      puts "SaaS mode: ENABLED"
      if ENV["SAAS"] == "true"
        puts "  (via SAAS environment variable)"
      else
        puts "  (via tmp/saas.txt marker)"
      end
    else
      puts "SaaS mode: DISABLED"
    end
  end

  desc "Setup SaaS mode (run migrations, create default workspace)"
  task setup: :environment do
    unless Campfire.saas?
      puts "SaaS mode is not enabled. Run 'bin/rails saas:enable' first."
      exit 1
    end

    puts "Setting up SaaS mode..."

    # Run untenanted migrations
    puts "\n--- Running untenanted migrations"
    Rake::Task["db:migrate:untenanted"].invoke

    # Check if default workspace exists
    if Workspace.exists?(external_id: 1000001)
      puts "\n--- Default workspace already exists (ID: 1000001)"
    else
      puts "\n--- Creating default workspace"
      # Create a default identity for the workspace creator
      email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
      creator = GlobalIdentity.find_or_create_by!(email_address: email.downcase)
      creator.verify! unless creator.verified?

      workspace = Workspace.create_with_database!(
        name: ENV.fetch("WORKSPACE_NAME", "Development Workspace"),
        creator: creator
      )

      puts "  Created workspace: #{workspace.name} (ID: #{workspace.external_id})"
      puts "  Admin: #{creator.email_address}"
    end

    puts "\n--- SaaS setup complete!"
    puts "\nTo start development:"
    puts "  bin/dev"
    puts "\nAccess URLs:"
    puts "  Landing: http://localhost:3000/"
    puts "  Workspace: http://localhost:3000/1000001/"
  end

  desc "Reset SaaS databases (drops and recreates all workspace databases)"
  task reset: :environment do
    unless Campfire.saas?
      puts "SaaS mode is not enabled."
      exit 1
    end

    print "This will destroy ALL workspaces and data. Are you sure? [y/N] "
    confirm = $stdin.gets.chomp.downcase
    unless confirm == "y"
      puts "Aborted."
      exit 0
    end

    puts "Resetting SaaS databases..."

    # Destroy all workspace databases
    Workspace.find_each do |workspace|
      puts "  Destroying workspace #{workspace.external_id}..."
      ApplicationRecord.destroy_tenant(workspace.external_id.to_s) rescue nil
      workspace.destroy!
    end

    # Reset untenanted database
    Rake::Task["db:drop:untenanted"].invoke rescue nil
    Rake::Task["db:create:untenanted"].invoke
    Rake::Task["db:migrate:untenanted"].invoke

    # Recreate default workspace
    Rake::Task["saas:setup"].reenable
    Rake::Task["saas:setup"].invoke
  end
end
