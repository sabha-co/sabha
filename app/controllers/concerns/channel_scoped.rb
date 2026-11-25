module ChannelScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_channel
  end

  private
    def set_channel
      @membership = Current.user.memberships.find_by!(channel_id: params[:channel_id])
      @channel = @membership.channel
      ensure_sub_channel_access
    end

    def set_channel_if_found
      @membership = Current.user.memberships.find_by(channel_id: params[:channel_id])
      @channel = @membership&.channel
      ensure_sub_channel_access
    end

    # A sub-channel follow row can outlive the parent access that justified it, so
    # deny one the user can no longer reach — the same re-check SubChannelAccessible
    # and User#reachable_channel apply.
    def ensure_sub_channel_access
      raise ActiveRecord::RecordNotFound if @channel&.stale_sub_channel_for?(Current.user)
    end

    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?(@channel)
    end
end
