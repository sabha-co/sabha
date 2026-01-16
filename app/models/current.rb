class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :request

  delegate :host, :protocol, to: :request, prefix: true, allow_nil: true

  def session=(value)
    super
    self.user = value&.user
  end

  def account
    @account ||= Account.active.first
  end
end
