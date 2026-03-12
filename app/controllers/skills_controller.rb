class SkillsController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :require_account

  def show
    expires_in 1.hour
    render formats: :text
  end

  private
    def require_account
      if Sabha.saas? && ApplicationRecord.current_tenant.blank?
        head :not_found
      elsif Current.account.nil?
        head :not_found
      end
    end
end
