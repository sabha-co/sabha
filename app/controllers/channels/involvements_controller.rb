class Channels::InvolvementsController < ApplicationController
  include ChannelScoped

  helper_method :from_sidebar

  before_action :set_involvement, only: %i[show notifications_ready]

  def show ; end

  def update
    @membership.update! involvement: params[:involvement]

    broadcast_involvement_changes

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to safe_return_to || channel_involvement_url(@channel, from_sidebar:) }
    end
  end

  def notifications_ready ; end

  private
    def safe_return_to
      params[:return_to] if params[:return_to].present? && safe_redirect_url?(params[:return_to])
    end

    def broadcast_involvement_changes
      broadcast_involvement_change_to_channel_nav
      broadcast_involvement_change_to_sidebar
      add_or_remove_channels_in_sidebar
    end

    def from_sidebar
      ActiveModel::Type::Boolean.new.cast(params[:from_sidebar])
    end

    def set_involvement
      @involvement = @membership.involvement
    end

    def broadcast_involvement_change_to_channel_nav
      broadcast_replace_to @membership, target: [ @channel, :involvement ],
                           partial: "channels/involvements/involvement",
                           locals: { channel: @channel, involvement: @membership.involvement, from_sidebar: false }
    end

    def broadcast_involvement_change_to_sidebar
      return if @channel.direct?

      list_name = @membership.sidebar_list_name
      broadcast_replace_to @membership.user, :channels,
                           target: [ @channel, helpers.dom_prefix(list_name, :list_node) ],
                           partial: "users/sidebars/channels/shared",
                           locals: { list_name:, membership: @membership }
    end

    def add_or_remove_channels_in_sidebar
      case
      when @membership.involved_in_invisible?
        # Channel is now hidden - remove from visible sections, add to hidden section
        Sidebar::SIDEBAR_SECTIONS.each do |list_name|
          broadcast_remove_to @membership.user, :channels, target: [ @channel, helpers.dom_prefix(list_name, :list_node) ]
        end
        broadcast_append_to @membership.user, :channels, target: :hidden_channels_list,
                            partial: "users/sidebars/channels/hidden", locals: { membership: @membership }
      when @membership.involvement_previously_was.inquiry.invisible?
        # Channel is now visible - remove from hidden section, add to correct section
        broadcast_remove_to @membership.user, :channels, target: [ @channel, :hidden_channel ]
        list_name = @membership.sidebar_list_name
        broadcast_append_to @membership.user, :channels, target: list_name,
                            partial: "users/sidebars/channels/shared", locals: { list_name:, membership: @membership },
                            attributes: { maintain_scroll: true }
      end
    end
end
