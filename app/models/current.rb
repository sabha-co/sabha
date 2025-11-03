class Current < ActiveSupport::CurrentAttributes
  attribute :user, :request

  delegate :host, :protocol, to: :request, prefix: true, allow_nil: true

  def account
    Account.active.first
  end
end
