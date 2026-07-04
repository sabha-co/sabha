# Standalone, permanent post page at /f/:slug. Renders the same post content as
# the in-app thread panel, but in the full layout with no redirect.
#
# Member-gated in v1: a logged-out visitor is sent through auth and returned to
# this URL (handled by Authentication#require_authentication); a logged-in
# non-member sees a join CTA — never the message list — via `viewable_by?`.
class ForumPostsController < RoomsController
  skip_before_action :set_room, only: :show
  skip_before_action :set_membership, only: :show
  skip_before_action :ensure_has_real_name, only: :show
  skip_before_action :remember_last_room_visited, only: :show

  before_action :set_post, only: :show

  def show
    return render_missing unless @post
    return render_gated   unless @post.viewable_by?(Current.user)

    @messages = find_messages
  end

  private
    def set_post
      @room = @post = Rooms::Post.active.find_by(slug: params[:slug])
      @forum = @post&.parent_room
      @membership = @post && Membership.find_by(room_id: @post.id, user_id: Current.user.id)
    end

    def render_gated
      render :gated, status: :forbidden
    end

    def render_missing
      render :missing, status: :not_found
    end
end
