class SkillsController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :require_account

  def show
    expires_in 1.hour
    render formats: :text
  end

  private
    def require_account
      head :not_found unless Current.account
    end
end
