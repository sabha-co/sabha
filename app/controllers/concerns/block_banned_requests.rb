module BlockBannedRequests
  extend ActiveSupport::Concern

  private
    def reject_banned_ip
      return if Sabha.saas? && ApplicationRecord.current_tenant.blank?
      head :too_many_requests if Ban.banned?(request.remote_ip)
    end
end
