class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :request

  # SaaS mode attributes (only used when Sabha.saas? is true)
  attribute :global_session, :workspace_membership

  delegate :host, :protocol, to: :request, prefix: true, allow_nil: true

  # Single-tenant mode: session sets user directly
  def session=(value)
    super
    self.user = value&.user unless Sabha.saas?
  end

  # SaaS mode: global_session sets workspace_membership
  def global_session=(value)
    super
    return if value.nil?

    if Sabha.saas? && ApplicationRecord.current_tenant.present?
      self.workspace_membership = value.global_identity
        &.workspace_memberships
        &.find_by(tenant: ApplicationRecord.current_tenant)
    end
  end

  def workspace_membership=(value)
    super
    @user = nil
  end

  # Delegate to global_identity from global_session (SaaS mode)
  def global_identity
    global_session&.global_identity
  end

  # In SaaS mode, user can be derived from workspace_membership
  # In single-tenant mode, user is set directly from session
  def user
    if Sabha.saas? && workspace_membership.present?
      @user ||= workspace_membership.user
    else
      super
    end
  end

  # Current workspace (SaaS mode only)
  # Returns the Workspace record for the current tenant
  # Logs a warning if tenant is set but workspace record doesn't exist (data inconsistency)
  def workspace
    return nil unless Sabha.saas? && ApplicationRecord.current_tenant.present?

    @workspace ||= begin
      ws = Workspace.find_by(external_id: ApplicationRecord.current_tenant)
      if ws.nil?
        Rails.logger.warn "[Current.workspace] Tenant #{ApplicationRecord.current_tenant} has no Workspace record"
      end
      ws
    end
  end

  def account
    return nil if Sabha.saas? && ApplicationRecord.try(:current_tenant).blank?
    @account ||= Account.sole
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # Reset cached values when attributes change
  def reset
    super
    @workspace = nil
    @account = nil
    @user = nil
  end
end
