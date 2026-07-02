class Rooms::ForumsController < RoomsController
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]
  before_action :remember_last_room_visited, only: :show
  before_action :ensure_permission_to_create_rooms, only: %i[ new create ]

  DEFAULT_FORUM_NAME = "New forum"

  # Gallery of posts, filtered by tag/Solved and sorted, with tags and
  # participant avatars preloaded for the cards.
  def show
    @posts = @room.posts(tag_ids: filter_tag_ids, solved: params[:solved], sort: params[:sort])
                  .includes(:tags, creator: { avatar_attachment: :blob })
    @participants = Rooms::Thread.preload_participant_creators(@posts)
  end

  def new
    @room = Rooms::Forum.new(name: DEFAULT_FORUM_NAME)
  end

  def create
    @room = Rooms::Forum.create_for(forum_params.except(:tags), users: Current.user)
    @room.create_tags_from_list(forum_params[:tags])

    broadcast_create_room
    redirect_to rooms_forum_url(@room)
  end

  def edit
  end

  def update
    old_name = @room.name

    @room.update! forum_params.except(:tags)
    @room.announce_rename(old_name, actor: Current.user) if @room.name != old_name

    RoomUpdateBroadcastJob.perform_later(@room)
    redirect_back fallback_location: rooms_forum_url(@room), notice: "Changes saved"
  end

  private
    def filter_tag_ids
      # Only accept scalar ids; a crafted `tag_ids[k]=v` hash param would
      # otherwise reach the query as nested arrays and error the gallery.
      Array(params[:tag_ids]).select { |id| id.is_a?(String) || id.is_a?(Integer) }.reject(&:blank?)
    end

    def forum_params
      params.require(:room).permit(:name, :description, :tags)
    end

    def broadcast_create_room
      @room.memberships.visible.includes(:user).each do |membership|
        broadcast_sidebar_room_added(membership.user, @room)
      end
    end
end
