# Creating a post in a forum. Distinct from Rooms::ThreadsController (which is
# reply-in-thread on an existing message): here the member authors a titled,
# tagged opening post. Any forum member may post; membership is the gate.
class Rooms::Forums::PostsController < ApplicationController
  before_action :set_forum
  before_action :set_post, only: %i[ edit update ]
  before_action :ensure_can_edit, only: %i[ edit update ]

  def new
  end

  def create
    post = @forum.post!(title: post_params[:title], body: post_params[:body], tag_ids: post_params[:tag_ids])

    redirect_to rooms_forum_url(@forum), notice: "Posted “#{post.title}”"
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "Could not create the post"
    render :new, status: :unprocessable_entity
  end

  # Title and tags are editable after creation (R8); the body lives in the
  # opening message and is edited through the normal message flow.
  def edit
  end

  def update
    @post.update!(name: post_params[:title])
    @forum.apply_tags(@post, post_params[:tag_ids])
    @post.broadcast_content_change

    redirect_to rooms_forum_url(@forum), notice: "Updated “#{@post.title}”"
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "Could not update the post"
    render :edit, status: :unprocessable_entity
  end

  private
    def set_forum
      @forum = Current.user.rooms.forums.find_by(id: params[:forum_id])
      redirect_to root_url, alert: "Forum not found or inaccessible" unless @forum
    end

    def set_post
      @post = @forum&.threads&.find_by(id: params[:id])
      redirect_to rooms_forum_url(@forum), alert: "Post not found" unless @post
    end

    def ensure_can_edit
      head :forbidden unless @post && Current.user.can_administer?(@post)
    end

    def post_params
      params.require(:post).permit(:title, :body, tag_ids: [])
    end
end
