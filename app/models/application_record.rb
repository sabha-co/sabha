class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Enable multi-tenant database isolation when SaaS mode is active
  # The activerecord-tenanted gem provides the `tenanted` macro
  tenanted if defined?(ActiveRecord::Tenanted) && Sabha.saas?

  # Namespaces a Rails.cache key by tenant so shared caches never bleed across
  # workspaces in SaaS mode. Self-hosted (single-tenant) uses the bare key.
  def self.tenant_cache_key(key)
    if Sabha.saas? && current_tenant.present?
      "#{current_tenant}/#{key}"
    else
      key
    end
  end
end
