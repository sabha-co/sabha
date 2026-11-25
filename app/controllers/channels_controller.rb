class ChannelsController < ApplicationController
  include SubChannelAccessible

  before_action :set_channel, only: %i[ show destroy ]
  before_action :set_membership, only: %i[ show ]
  before_action :ensure_has_real_name, only: %i[ show ]
  before_action :ensure_can_administer, only: %i[ destroy ]
  before_action :remember_last_channel_visited, only: %i[ show ]

  def index
    if (channel = Current.user.channels.without_threads.last)
      redirect_to channel_url(channel)
    else
      redirect_to root_url
    end
  end

  def show
    if @channel.thread? && @channel.parent_message
      redirect_to channel_at_message_path(@channel.parent_message.channel, @channel.parent_message)
      return
    end

    return render_forum_gallery if @channel.forum?

    @messages = find_messages
  end

  def destroy
    deactivate_channel
    redirect_to root_url
  rescue Channel::CannotDeleteOriginalError
    redirect_back fallback_location: root_url, alert: "The original channel can't be deleted"
  end

  private
    def deactivate_channel
      @channel.deactivate

      broadcast_sidebar_channel_removed(Current.account, @channel)
    end

    def set_channel
      channel = Current.user.channels.includes(parent_message: { creator: :avatar_attachment }).find_by(id: params[:channel_id] || params[:id])
      # A sub-channel (forum post or chat thread) derives access from its parent: a
      # parent member can open one without a membership row of their own, and a
      # stale row must not grant access after they leave the parent. So fall back
      # to parent-derived access, then re-check viewable_by? for any sub-channel.
      channel ||= viewable_sub_channel(params[:channel_id] || params[:id])
      channel = deny_stale_sub_channel(channel)

      if channel && serves?(channel)
        @channel = channel
      else
        redirect_to root_url, alert: "Channel not found or inaccessible"
      end
    end

    # Whether this channel is one the namespace is about. #show here serves all six
    # types, so the base answers yes to everything; a subclass that edits,
    # converts, or deletes channels narrows it to its own. Without that narrowing
    # one namespace reaches another's channels — the /channels/opens form loads a
    # direct channel or a thread and turns it into a channel the account can browse.
    # Asked after both lookups above, since either can surface a channel this
    # controller has no business touching.
    def serves?(channel)
      true
    end

    def set_membership
      return unless @channel
      @membership = Membership.find_by(channel_id: @channel.id, user_id: Current.user.id)
    end

    def ensure_has_real_name
      redirect_to user_profile_path, alert: "Please enter your name" if Current.user.default_name?
    end

    def ensure_can_administer
      head :forbidden unless @channel && Current.user.can_administer?(@channel)
    end

    # A forum is a channel like any other — it renders here at /channels/:id (the
    # gallery of posts) instead of the message stream. No separate route/UI.
    def render_forum_gallery
      @deep_linked_post = deep_linked_post

      posts = @channel.posts(solved: params[:solved], sort: params[:sort])
                   .includes(:solution, creator: { avatar_attachment: :blob })
      set_page_and_extract_portion_from posts, per_page: 20
      @posts = @page.records
      @participants = Channels::Post.preload_participant_creators(@posts)

      # Only a lazy pagination request (which carries ?page=N) wants the append
      # stream. A plain visit — including the redirect-follow after creating a
      # forum or post, which Turbo sends with a turbo-stream Accept header but no
      # page param — must render the full gallery page, or the browser applies a
      # no-op stream against an off-page target and never navigates.
      render "channels/forums/gallery", formats: [ params[:page].present? ? :turbo_stream : :html ]
    end

    # A permalink or push deep-links a post as ?post=<slug> on its forum's URL.
    # The gallery renders behind it and the layout points the thread-panel frame
    # at this post, so the panel opens over the gallery on load. A stale or
    # non-viewable slug just yields the plain gallery.
    def deep_linked_post
      return if params[:post].blank?

      post = Channels::Post.active.find_by(parent_channel_id: @channel.id, slug: params[:post])
      post if post&.viewable_by?(Current.user)
    end

    def find_messages
      messages = @channel.messages.for_display.with_bookmark_status_for(Current.user)
      @first_unread_message = first_unread

      anchor = target_message(messages) || @first_unread_message
      result = anchor ? messages.page_around(anchor) : messages.last_page

      Message.with_thread_participants(with_thread_parent(result))
    end

    def first_unread
      # A forum member can view a post without a membership (access is
      # forum-derived), so there may be no unread state to anchor on.
      return unless @membership&.unread?
      @membership.first_unread_message
    end

    def target_message(messages)
      messages.find_by(id: params[:message_id])
    end

    def with_thread_parent(messages)
      return messages unless @channel.thread? && @channel.parent_message

      # Parent message bookmark status uses fallback query (single record, acceptable)
      return [ @channel.parent_message ] if messages.empty?
      showing_beginning_of_thread?(messages) ? [ @channel.parent_message, *messages ] : messages
    end

    def showing_beginning_of_thread?(messages)
      first_in_thread = @channel.messages.ordered.first
      first_in_thread && messages.first&.id == first_in_thread.id
    end

    def load_users_for_access_management
      all_members = @channel.visible_users.active.includes(avatar_attachment: :blob).ordered
      @preview_members = all_members.limit(10)
      @remaining_members = all_members.offset(10)
      @available_users_json = User.active.verified.where.not(id: all_members.select(:id))
                                  .ordered.pluck(:id, :name)
                                  .map { |id, name| { id: id, name: name } }
    end

    def channel_params
      params.require(:channel).permit(:name, :description, :auto_join)
    end

    def ensure_permission_to_create_channels
      if Current.account.settings.restrict_channel_creation_to_administrators? && !Current.user.administrator?
        head :forbidden
      end
    end
end
