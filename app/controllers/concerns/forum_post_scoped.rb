# Loads @forum and @post for the forum-post controllers (posts, solutions) and
# authorizes edits to the post's author or an admin. The post is a Rooms::Post
# scoped to a forum the current user belongs to, so a non-member never resolves
# one — membership is the gate.
module ForumPostScoped
  extend ActiveSupport::Concern

  private
    def set_forum
      @forum = Current.user.rooms.forums.find_by(id: params[:forum_id])
      redirect_to root_url, alert: "Forum not found or inaccessible" unless @forum
    end

    def set_post
      # Active- and forum-scoped, so a deleted post — or one in another forum —
      # can't be edited or solved through these nested routes. A plain finder
      # (not @forum.posts, the sorted gallery scope) avoids an ORDER BY on a
      # by-id lookup.
      @post = @forum && Rooms::Post.active.find_by(parent_room_id: @forum.id, id: params[:post_id] || params[:id])
      redirect_to room_url(@forum), alert: "Post not found" unless @post
    end

    def ensure_can_administer_post
      head :forbidden unless @post && Current.user.can_administer?(@post)
    end
end
