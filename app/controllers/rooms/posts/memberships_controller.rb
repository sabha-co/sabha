# Follow (create) / Unfollow (destroy) a forum post — the state-as-records form
# of "notify me of replies without having replied." Access derives from forum
# membership; this manages only the current user's own follow on the post.
class Rooms::Posts::MembershipsController < ApplicationController
  before_action :set_post

  def create
    @post.follow!(Current.user)
    respond_with_follow_change
  end

  def destroy
    @post.unfollow!(Current.user)
    respond_with_follow_change
  end

  private
    # Flip the Follow/Unfollow button in its frame, and refresh this post's gallery
    # card so its "Following" pill updates for the actor without a reload. Both ride
    # one turbo_stream straight to the actor — the card replace is a direct response,
    # not a broadcast, so it never touches other viewers' viewer-agnostic cards. A
    # missing card target (off the current gallery page) is a harmless no-op; JS off
    # falls back to the full redirect.
    def respond_with_follow_change
      if turbo_frame_request?
        render turbo_stream: [
          turbo_stream.replace(helpers.dom_id(@post, :follow),
            partial: "rooms/forums/posts/follow_control", locals: { post: @post }),
          turbo_stream.replace(helpers.dom_id(@post, :card),
            partial: "rooms/forums/post_card",
            locals: { post: @post, forum: @post.parent_room,
                      participants: Rooms::Post.preload_participant_creators([ @post ]),
                      viewer: Current.user })
        ]
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
