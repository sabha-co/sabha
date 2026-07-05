# The in-app post panel: a Rooms::Post rendered into the gallery's side panel
# (thread_panel_frame), the post counterpart of Rooms::ThreadsController#show.
# Access derives from forum membership (viewable_by?), so a forum member can open
# a post they haven't followed — no per-post membership required.
class Rooms::PostsController < RoomsController
  skip_before_action :set_room, only: :show
  skip_before_action :set_membership, only: :show
  skip_before_action :ensure_has_real_name, only: :show
  skip_before_action :remember_last_room_visited, only: :show

  before_action :set_post, only: :show

  def show
    return head :not_found unless @post
    return head :forbidden unless @post.viewable_by?(Current.user)

    @messages = find_messages
    render layout: false
  end

  private
    def set_post
      @room = @post = Rooms::Post.active.find_by(id: params[:id])
      @forum = @post&.parent_room
      @membership = @post && Membership.find_by(room_id: @post.id, user_id: Current.user.id)
    end
end
