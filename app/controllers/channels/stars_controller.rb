class Channels::StarsController < ApplicationController
  include ChannelScoped

  before_action :ensure_starrable

  def create
    @membership.update!(starred: true)

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to channel_url(@channel) }
    end
  end

  def destroy
    @membership.update!(starred: false)

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to channel_url(@channel) }
    end
  end

  private

  def ensure_starrable
    head :unprocessable_entity if @channel.direct? || @channel.sub_channel? || @membership.involved_in_invisible?
  end
end
