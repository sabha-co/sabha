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

  # Mirror session=: derive Current.user from the canonical input.
  # Caller must ensure ApplicationRecord.current_tenant is set first —
  # WorkspaceMembership#user wraps its own with_tenant block, but value
  # must be the membership for the active tenant.
  def workspace_membership=(value)
    super
    self.user = value&.user
  end

  # Delegate to global_identity from global_session (SaaS mode)
  def global_identity
    global_session&.global_identity
  end

  # workspace and account are 1:1 derivations of ApplicationRecord.current_tenant,
  # not independent inputs — see docs/multi-tenant/activerecord-tenanted-guide.md.
  # The gem guarantees current_tenant is set in every tenant-aware context (HTTP,
  # ActiveJob#perform_now, ActionCable around_command, with_tenant blocks), so
  # lazy resolution from current_tenant is always correct. Modeling them as
  # `attribute :…` would force assignment plumbing at every entrypoint with no
  # added correctness — the gem already centralizes that.
  def workspace
    return nil unless Sabha.saas? && ApplicationRecord.current_tenant.present?
    @workspace ||= Workspace.find_by(external_id: ApplicationRecord.current_tenant)
  end

  def account
    return nil if Sabha.saas? && ApplicationRecord.try(:current_tenant).blank?
    @account ||= Account.sole
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def reset
    super
    @workspace = nil
    @account = nil
  end
end
