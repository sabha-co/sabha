class MarketingController < ApplicationController
  include AccountsHelper

  allow_unauthenticated_access
  layout "marketing"

  before_action :restore_authentication, :redirect_signed_in_user_to_chat, except: [ :join, :stats ]

  def show
    # Simplified marketing page - no dynamic data needed
  end

  def join
    redirect_to join_path(Current.account.join_code)
  end

  def stats
    member_count = User.active.non_suspended.count
    online_count = online_users_count
    render json: {
      member_count: member_count,
      online_count: online_count
    }
  end
end
