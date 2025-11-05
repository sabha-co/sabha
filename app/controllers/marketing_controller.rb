class MarketingController < ApplicationController
  include AccountsHelper

  allow_unauthenticated_access
  layout "marketing"

  before_action :ensure_account_exists
  before_action :restore_authentication, :redirect_signed_in_user_to_chat, except: [ :join, :stats ]

  def show
    # Simplified marketing page - no dynamic data needed
  end

  def join
    if Current.account.open_registration_value
      redirect_to join_path(Current.account.join_code)
    else
      head :not_found
    end
  end

  def stats
    member_count = User.active.non_suspended.count
    online_count = online_users_count
    render json: {
      member_count: member_count,
      online_count: online_count
    }
  end

  private

  def ensure_account_exists
    redirect_to first_run_path unless Account.any?
  end
end
