class Rooms::ClosedsController < RoomsController
  before_action :set_room, only: %i[ show edit update destroy ]
  before_action :set_membership, only: %i[ edit ]
  before_action :ensure_can_administer, only: %i[ update destroy ]
  before_action :remember_last_room_visited, only: :show
  before_action :force_room_type, only: %i[ edit update ]
  before_action :ensure_permission_to_create_rooms, only: %i[ new create ]

  DEFAULT_ROOM_NAME = "New room"
  USER_SEARCH_LIMIT = 50

  def show
    redirect_to room_url(@room)
  end

  def new
    @room  = Rooms::Closed.new(name: DEFAULT_ROOM_NAME)
    @selected_users = [ Current.user ]
    @unselected_users = User.active.verified.where.not(id: Current.user.id).includes(avatar_attachment: :blob).ordered.limit(10)
    @total_user_count = User.active.verified.count
  end

  def users
    @room = Rooms::Closed.new
    @selected_user_ids = Array(params[:selected_ids]).map(&:to_i)
    @users = search_users(params[:query], exclude_ids: @selected_user_ids)

    render partial: "rooms/closeds/user_results", locals: { users: @users, room: @room, selected_user_ids: @selected_user_ids }
  end

  def create
    room = Rooms::Closed.create_for(room_params, users: grantees)

    broadcast_create_room(room)
    redirect_to room_url(room)
  end

  def edit
    @selected_users = @room.users.active.includes(avatar_attachment: :blob).ordered
    selected_ids = @selected_users.pluck(:id)
    @unselected_users = User.active.verified.where.not(id: selected_ids).includes(avatar_attachment: :blob).ordered.limit(10)
    @total_user_count = User.active.verified.count
  end

  def update
    @room.update! room_params
    @room.memberships.revise(granted: grantees, revoked: revokees)

    RoomUpdateBroadcastJob.perform_later(@room)
    redirect_to room_url(@room)
  end

  private
    def search_users(query, exclude_ids: [])
      return [] if query.blank?

      scope = User.active.verified.filtered_by(query)
      scope = scope.where.not(id: exclude_ids) if exclude_ids.present?
      scope.includes(avatar_attachment: :blob).ordered.limit(USER_SEARCH_LIMIT)
    end

    # Allows us to edit an open room and turn it into a closed one on saving.
    def force_room_type
      @room = @room.becomes!(Rooms::Closed)
    end

    def grantees
      User.where(id: grantee_ids)
    end

    def revokees
      @room.users.where.not(id: grantee_ids)
    end

    def grantee_ids
      params.fetch(:user_ids, [])
    end

    def broadcast_create_room(room)
      for_each_sidebar_section do |list_name|
        # render_to_string runs in request context (has script_name), so URLs are tenant-safe.
        # Render once and reuse: new rooms have no per-member unread state to differentiate.
        html = render_to_string(partial: "users/sidebars/rooms/shared", locals: { list_name:, room: room })

        room.memberships.visible.includes(:user).each do |membership|
          broadcast_append_to membership.user, :rooms, target: list_name, html: html, attributes: { maintain_scroll: true }
        end
      end
    end
end
