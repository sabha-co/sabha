class RoomsController < ApplicationController
  before_action :set_room, only: %i[ show destroy ]
  before_action :set_membership, only: %i[ show ]
  before_action :ensure_has_real_name, only: %i[ show ]
  before_action :ensure_can_administer, only: %i[ destroy ]
  before_action :remember_last_room_visited, only: %i[ show ]

  def index
    if (room = Current.user.rooms.last)
      redirect_to room_url(room)
    else
      redirect_to root_url
    end
  end

  def show
    @messages = find_messages
  end

  def destroy
    deactivate_room
    redirect_to root_url
  end

  private
    def deactivate_room
      @room.deactivate

      broadcast_remove_room
    end

    def set_room
      if room = Current.user.rooms.includes(parent_message: { creator: :avatar_attachment }).find_by(id: params[:room_id] || params[:id])
        @room = room
      else
        redirect_to root_url, alert: "Room not found or inaccessible"
      end
    end

    def set_membership
      return unless @room
      @membership = Membership.find_by(room_id: @room.id, user_id: Current.user.id)
    end

    def ensure_has_real_name
      redirect_to user_profile_path, alert: "Please enter your name" if Current.user.default_name?
    end

    def ensure_can_administer
      head :forbidden unless @room && Current.user.can_administer?(@room)
    end

    def find_messages
      messages = @room.messages.for_display.with_bookmark_status_for(Current.user)
      @first_unread_message = first_unread_from(messages)

      anchor = target_message(messages) || @first_unread_message
      result = anchor ? messages.page_around(anchor) : messages.last_page

      with_thread_parent(result)
    end

    def first_unread_from(messages)
      return unless @membership.unread?
      messages.ordered.since(@membership.unread_at).first
    end

    def target_message(messages)
      messages.find_by(id: params[:message_id])
    end

    def with_thread_parent(messages)
      return messages unless @room.thread? && @room.parent_message

      # Parent message bookmark status uses fallback query (single record, acceptable)
      return [ @room.parent_message ] if messages.empty?
      showing_beginning_of_thread?(messages) ? [ @room.parent_message, *messages ] : messages
    end

    def showing_beginning_of_thread?(messages)
      first_in_thread = @room.messages.ordered.first
      first_in_thread && messages.first&.id == first_in_thread.id
    end

    def room_params
      params.require(:room).permit(:name)
    end

    def ensure_permission_to_create_rooms
      if Current.account.settings.restrict_room_creation_to_administrators? && !Current.user.administrator?
        head :forbidden
      end
    end

    def broadcast_remove_room
      for_each_sidebar_section do |list_name|
        broadcast_remove_to :rooms, target: [ @room, helpers.dom_prefix(list_name, :list_node) ]
      end
    end
end
