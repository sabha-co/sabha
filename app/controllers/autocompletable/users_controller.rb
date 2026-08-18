class Autocompletable::UsersController < ApplicationController
  include SubRoomAccessible

  # The mention prompt shows a short, tap-friendly menu; the DM recipient picker
  # loads a longer list and filters it client-side.
  MENTION_PROMPT_LIMIT = 5
  RECIPIENT_PICKER_LIMIT = 20

  def index
    @users = add_everyone_mention_if_applicable(find_autocompletable_users)

    respond_to do |format|
      format.html { render layout: false } # <lexxy-prompt-item> elements for the mention prompt
      format.json
    end
  end

  private
    def find_autocompletable_users
      query.present? ? users_scope.matching(query, limit: result_limit) : users_scope.limit(result_limit)
    end

    # The mention prompt sends `filter`; the DM recipient picker sends `query`
    # and needs the fuller list to filter against in the browser.
    def result_limit
      params.key?(:filter) ? MENTION_PROMPT_LIMIT : RECIPIENT_PICKER_LIMIT
    end

    # The rich text editor's mention prompt filters with `filter`, the DM
    # recipient autocomplete inputs with `query`.
    def query
      params[:filter].presence || params[:query].presence
    end

    def room
      return @room if defined?(@room)
      @room = resolve_room
    end

    # A member can open and reply to a sub-room (forum post or chat thread)
    # without holding a per-sub-room membership (access derives from the parent),
    # so resolve those by viewable_by? too — Current.user.rooms only covers rooms
    # they belong to and would 404 the @mention picker for a member who hasn't
    # engaged yet. Rooms they genuinely can't reach still raise, exactly as before.
    def resolve_room
      return unless params[:room_id].present?

      room = Current.user.rooms.find_by(id: params[:room_id]) || viewable_sub_room(params[:room_id])
      deny_stale_sub_room(room) || raise(ActiveRecord::RecordNotFound)
    end

    def users_scope
      mentionable_base.active.without_default_names.recent_posters_first(room&.id).with_attached_avatar
    end

    # A provisional DM has no room yet, so its composer scopes the mention picker to
    # the chosen recipients via user_ids — matching what room.mentionable_users
    # returns once the DM exists. Without it the picker falls back to every user and
    # lets you "mention" a non-member, rendering a mention that never notifies them.
    def mentionable_base
      return room.mentionable_users if room
      return User.where(id: params[:user_ids]) if params[:user_ids].present?

      User.all
    end

    def add_everyone_mention_if_applicable(users)
      # Only show @everyone for admins in open rooms, and only when it matches the
      # filter (the mention prompt filters server-side, so it can't drop it later).
      return users unless Current.user&.administrator?
      return users unless room&.is_a?(Rooms::Open)
      return users unless everyone_matches_query?

      users + [ Everyone.new ]
    end

    def everyone_matches_query?
      query.blank? || "everyone".include?(query.downcase.delete("@"))
    end
end
