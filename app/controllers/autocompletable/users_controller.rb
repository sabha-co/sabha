class Autocompletable::UsersController < ApplicationController
  def index
    @users = find_autocompletable_users
    @users = add_everyone_mention_if_applicable(@users)
  end

  private
    def find_autocompletable_users
      exact_name_matches = users_scope.by_first_name(params[:query])
      all_matches = users_scope.filtered_by(params[:query]).limit(20)

      (exact_name_matches + all_matches).uniq
    end

    def room
      @room ||= Current.user.rooms.find(params[:room_id]) if params[:room_id].present?
    end

    def users_scope
      base = room&.users || User.all
      base.active.without_default_names.recent_posters_first(room&.id).with_attached_avatar
    end

    def add_everyone_mention_if_applicable(users)
      # Only show @everyone for admins in open rooms
      return users unless Current.user&.administrator?
      return users unless room&.is_a?(Rooms::Open)

      users + [ Everyone.new ]
    end
end
