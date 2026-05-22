module Membership::Connectable
  extend ActiveSupport::Concern

  CONNECTION_TTL = 60.seconds

  included do
    scope :connected,    -> { where(connected_at: CONNECTION_TTL.ago..) }
    scope :disconnected, -> { where(connected_at: [ nil, ...CONNECTION_TTL.ago ]) }

    after_update_commit  :reset_user_connections_if_deactivated
    after_destroy_commit :reset_user_connections
  end

  ACTIVITY_TIERS = { active: 10.minutes, away: 1.hour, recently_active: 24.hours }.freeze

  class_methods do
    def disconnect_all
      connected.update_all connected_at: nil, connections: 0, updated_at: Time.current
    end

    def connect(membership, connections)
      where(id: membership.id).update_all(connections: connections, connected_at: Time.current, unread_at: nil, unread_notifications_count: 0)
    end

    def last_connected_at_for(user_ids)
      where(user_id: user_ids).group(:user_id).maximum(:connected_at)
    end

    def activity_status(connected_at)
      return :offline unless connected_at

      if connected_at >= ACTIVITY_TIERS[:active].ago
        :active
      elsif connected_at >= ACTIVITY_TIERS[:away].ago
        :away
      else
        :offline
      end
    end

    def activity_statuses_for(user_ids)
      last_connected_at_for(user_ids).transform_values { |t| activity_status(t) }
    end

    def online_user_count(since: ACTIVITY_TIERS[:active])
      where(connected_at: since.ago..).select(:user_id).distinct.count
    end

    # Email-only presence check: a user is away when no membership in this
    # tenant has been connected within the away tier (1 hour). Distinct from
    # `connected?` (60s) which gates push — email asks "has the user been gone
    # long enough that an email is the right way to reach them?"
    def workspace_locally_away?(user_id)
      last_seen = last_connected_at_for([ user_id ])[user_id]
      return true if last_seen.nil?
      last_seen < ACTIVITY_TIERS[:away].ago
    end
  end

  def connected?
    connected_at? && connected_at >= CONNECTION_TTL.ago
  end

  def present
    self.class.connect(self, connected? ? connections + 1 : 1)
  end

  def connected
    increment_connections
    touch :connected_at
  end

  def disconnected
    decrement_connections
    update! connected_at: nil if connections < 1
  end

  def refresh_connection
    increment_connections unless connected?
    touch :connected_at
  end

  def increment_connections
    connected? ? increment!(:connections, touch: true) : update!(connections: 1)
  end

  def decrement_connections
    connected? ? decrement!(:connections, touch: true) : update!(connections: 0)
  end

  private
    def reset_user_connections_if_deactivated
      user.reset_remote_connections if deactivated?
    end

    def reset_user_connections
      user.reset_remote_connections
    end
end
