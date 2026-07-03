# Loads @forum and @post for the forum-post controllers (posts, solutions) and
# authorizes edits to the post's OP or an admin. The post is a Rooms::Thread
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
      # `.active` so a deleted post can't be edited or solved through these
      # nested routes — its /f/:slug page already 404s, and the forum.threads
      # association isn't active-scoped (it joins through the still-active
      # opening message).
      @post = @forum&.threads&.active&.find_by(id: params[:post_id] || params[:id])
      redirect_to room_url(@forum), alert: "Post not found" unless @post
    end

    def ensure_can_administer_post
      head :forbidden unless @post && Current.user.can_administer?(@post)
    end
end
