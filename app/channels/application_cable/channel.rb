module ApplicationCable
  class Channel < ActionCable::Channel::Base
    include TenantContext if defined?(TenantContext)

    private
      # Fallback for non-SaaS mode (TenantContext not loaded)
      unless method_defined?(:with_tenant_context) || private_method_defined?(:with_tenant_context)
        def with_tenant_context(&block)
          yield
        end
      end
  end
end
