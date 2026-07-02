# Creating a post in a forum. Distinct from Rooms::ThreadsController (which is
# reply-in-thread on an existing message): here the member authors a titled,
# tagged opening post. Any forum member may post; membership is the gate.
class Rooms::Forums::PostsController < ApplicationController
  before_action :set_forum

  def new
  end

  def create
    post = @forum.post!(title: post_params[:title], body: post_params[:body], tag_ids: post_params[:tag_ids])

    redirect_to rooms_forum_url(@forum), notice: "Posted “#{post.title}”"
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "Could not create the post"
    render :new, status: :unprocessable_entity
  end

  private
    def set_forum
      @forum = Current.user.rooms.forums.find_by(id: params[:forum_id])
      redirect_to root_url, alert: "Forum not found or inaccessible" unless @forum
    end

    def post_params
      params.require(:post).permit(:title, :body, tag_ids: [])
    end
end
