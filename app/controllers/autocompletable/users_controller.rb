class Autocompletable::UsersController < ApplicationController
  def index
    @users = find_autocompletable_users
    @users = add_everyone_mention_if_applicable(@users)
  end

  private
    def find_autocompletable_users
      params[:query].present? ? users_scope.matching(params[:query]) : users_scope.limit(20)
    end

    def room
      return @room if defined?(@room)
      @room = resolve_room
    end

    # A forum member can open and reply to a post without holding a per-post
    # membership (access derives from the forum), so resolve posts by viewable_by?
    # too — Current.user.rooms only covers rooms they belong to and would 404 the
    # @mention picker for a member who hasn't followed the post yet. Rooms they
    # genuinely can't reach still raise, exactly as before.
    def resolve_room
      return unless params[:room_id].present?

      Current.user.rooms.find_by(id: params[:room_id]) ||
        Current.user.reachable_post(params[:room_id]) ||
        raise(ActiveRecord::RecordNotFound)
    end

    def users_scope
      base = room ? room.mentionable_users : User.all
      base.active.without_default_names.recent_posters_first(room&.id).with_attached_avatar
    end

    def add_everyone_mention_if_applicable(users)
      # Only show @everyone for admins in open rooms
      return users unless Current.user&.administrator?
      return users unless room&.is_a?(Rooms::Open)

      users + [ Everyone.new ]
    end
end
