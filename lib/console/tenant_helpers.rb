module Console
  module TenantHelpers
    def tenants(external_id = nil)
      return tenant(external_id) if external_id

      Workspace.order(:external_id).each do |w|
        active = ApplicationRecord.current_tenant == w.external_id.to_s ? " (active)" : ""
        puts "  #{w.external_id} - #{w.name}#{active}"
      end
      nil
    end

    def tenant(external_id)
      ApplicationRecord.current_tenant = external_id.to_s
      workspace = Workspace.find_by(external_id: external_id)
      puts "Switched to tenant #{external_id} (#{workspace&.name || 'unknown'})"
    end

    def current_tenant
      id = ApplicationRecord.current_tenant
      return puts "No active tenant" unless id

      workspace = Workspace.find_by(external_id: id)
      puts "#{id} - #{workspace&.name || 'unknown'}"
    end

    def tenant_reset
      ApplicationRecord.current_tenant = nil
      puts "Tenant context cleared"
    end
  end
end
