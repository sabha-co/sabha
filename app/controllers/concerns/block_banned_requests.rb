module BlockBannedRequests
  extend ActiveSupport::Concern

  included do
    before_action :reject_banned_ip, unless: :safe_request?
  end

  private
    def reject_banned_ip
      return if Sabha.saas? && ApplicationRecord.current_tenant.blank?
      head :too_many_requests if Ban.banned?(request.remote_ip)
    end

    def safe_request?
      request.get? || request.head?
    end
end
