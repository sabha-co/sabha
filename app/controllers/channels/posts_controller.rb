# The in-app post panel: a Channels::Post rendered into the gallery's side panel
# (thread_panel_frame), the post counterpart of Channels::ThreadsController#show.
# Access derives from forum membership (viewable_by?), so a forum member can open
# a post they haven't followed — no per-post membership required.
class Channels::PostsController < ChannelsController
  skip_before_action :set_channel, only: :show
  skip_before_action :set_membership, only: :show
  skip_before_action :ensure_has_real_name, only: :show
  skip_before_action :remember_last_channel_visited, only: :show

  before_action :set_post, only: :show

  def show
    return head :not_found unless @post
    return head :forbidden unless @post.viewable_by?(Current.user)

    @messages = find_messages
    render layout: false
  end

  private
    def set_post
      @channel = @post = Channels::Post.active.find_by(id: params[:id])
      @forum = @post&.parent_channel
      @membership = @post && Membership.find_by(channel_id: @post.id, user_id: Current.user.id)
    end
end
