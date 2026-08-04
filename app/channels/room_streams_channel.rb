# Authorizes the Turbo streams that carry a room's contents, at the moment the
# subscription is made, so that losing access actually stops delivery.
#
# Turbo's stock channel verifies only the signature on the stream name. That name
# carries no expiry and no binding to a user, so one harvested while a member
# keeps working after the membership is gone — and it works just as well for
# anyone who copies it, member or not. Reconnecting doesn't help: the client
# replays its subscriptions onto the fresh socket.
#
# The room is derived from the verified stream name rather than taken as a
# parameter, so there's nothing for a subscriber to point somewhere else. The
# subscriber doesn't get to pick the channel either — Turbo::StreamsChannel turns
# these names away, so this is the only door onto them. See
# RoomStreamsAreAuthorized and config/initializers/turbo_streams_authorization.rb.
class RoomStreamsChannel < ApplicationCable::Channel
  extend  Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  # The trailing segment of the stream names this channel guards: a room's
  # message stream and a forum's gallery of posts.
  GUARDED_SUFFIXES = %w[ messages posts ].freeze

  # A stream name can point at a record that's since been deleted or — in SaaS —
  # one minted in another workspace, which the tenanted locator refuses outright
  # rather than returning nil. Nothing resolves either way, and both end in the
  # same plain reject. Named rather than listed inline because the tenanted error
  # class doesn't exist in self-hosted mode.
  LOOKUP_FAILURES = [
    ActiveRecord::RecordNotFound,
    "ActiveRecord::Tenanted::Error".safe_constantize
  ].compact.freeze

  class << self
    # True for the stream names this channel exists to guard, whoever is asking.
    # Deliberately free of database work — Turbo::StreamsChannel consults this on
    # every subscribe, guarded or not.
    def guarded_stream?(stream_name)
      GUARDED_SUFFIXES.include? segments(stream_name).last
    end

    # Stream names are the streamables' GlobalID params joined with ":". A GID
    # param is base64, which has no colons of its own, so the segments split back
    # out cleanly.
    def segments(stream_name)
      stream_name.to_s.split(":")
    end
  end

  def subscribed
    if stream_name = authorized_stream_name
      stream_from stream_name
    else
      reject
    end
  end

  private
    def authorized_stream_name
      stream_name = verified_stream_name_from_params
      stream_name if stream_name.present? && authorized?(stream_name)
    end

    # Two shapes reach here: "<room>:messages" and "<room>:posts", which every
    # member of the room shares, and "<user>:<room>:messages", which carries one
    # person's own state (their bookmark marks) and so belongs to them alone.
    def authorized?(stream_name)
      return false unless self.class.guarded_stream?(stream_name)

      segments = self.class.segments(stream_name)

      with_tenant_context do
        reachable_room?(segments[-2]) && (segments.size < 3 || own_gid_param?(segments[-3]))
      end
    end

    def reachable_room?(gid_param)
      room = locate(gid_param, Room)
      # A sub-room (forum post or chat thread) derives access from its parent, so
      # a forum member reaches a post's stream without a row of their own, and a
      # stale row stops granting it once they lose the parent. Same rule
      # RoomChannel applies to typing and presence.
      room.present? && current_user&.reachable_room(room.id).present?
    end

    def own_gid_param?(gid_param)
      current_user.present? && locate(gid_param, User) == current_user
    end

    def locate(gid_param, klass)
      GlobalID::Locator.locate gid_param, only: klass
    rescue *LOOKUP_FAILURES
      nil
    end
end
