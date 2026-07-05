# Follow (create) / Unfollow (destroy) a forum post — the state-as-records form
# of "notify me of replies without having replied." Access derives from forum
# membership; this manages only the current user's own follow on the post.
class Rooms::Posts::MembershipsController < ApplicationController
  before_action :set_post

  def create
    @post.follow!(Current.user)
    respond_with_follow_control
  end

  def destroy
    @post.unfollow!(Current.user)
    respond_with_follow_control
  end

  private
    # In the browser the Follow/Unfollow button lives in a turbo frame, so flip it
    # in place — the state change shows without reloading and dropping the panel.
    # A non-frame request (JS off) falls back to the full redirect.
    def respond_with_follow_control
      if turbo_frame_request?
        render partial: "rooms/forums/posts/follow_control", locals: { post: @post }
      else
        redirect_back fallback_location: room_url(@post.parent_room, post: @post.slug)
      end
    end

    def set_post
      @post = Rooms::Post.active.find_by(id: params[:post_id])
      return head :not_found unless @post
      head :forbidden unless @post.viewable_by?(Current.user)
    end
end
