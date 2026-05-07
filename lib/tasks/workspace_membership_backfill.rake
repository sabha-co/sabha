# frozen_string_literal: true

namespace :workspace_membership do
  desc "Backfill workspace_memberships.user_active by reading each workspace's User.status"
  task backfill_user_active: :environment do
    unless Sabha.saas?
      puts "SaaS mode is not enabled. Run with SAAS=true or bin/rails saas:enable"
      exit 1
    end

    flipped = 0
    skipped = 0

    WorkspaceMembership.where(user_active: true).find_each do |m|
      next skipped += 1 if m.user_id.blank?

      ApplicationRecord.with_tenant(m.tenant) do
        user = User.find_by(id: m.user_id)
        if user && !user.active?
          m.update_column(:user_active, false)
          flipped += 1
          puts "  Marked inactive: tenant=#{m.tenant} user_id=#{m.user_id} status=#{user.status}"
        end
      rescue ActiveRecord::Tenanted::TenantDoesNotExistError
        skipped += 1
      end
    end

    puts "Done. Flipped #{flipped} membership(s) to inactive. Skipped #{skipped}."
  end
end
