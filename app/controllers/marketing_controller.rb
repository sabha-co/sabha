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
    # Registration requires an invite link - this endpoint no longer exposes the join code
    head :not_found
  end

  def stats
    member_count = User.active.count
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
