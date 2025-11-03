module Membership::Connectable
  extend ActiveSupport::Concern

  CONNECTION_TTL = 60.seconds

  included do
    scope :connected,    -> { where(connected_at: CONNECTION_TTL.ago..) }
    scope :disconnected, -> { where(connected_at: [ nil, ...CONNECTION_TTL.ago ]) }
  end

  class_methods do
    def disconnect_all
      connected.update_all connected_at: nil, connections: 0, updated_at: Time.current
    end

    def connect(membership, connections)
      where(id: membership.id).update_all(connections: connections, connected_at: Time.current, unread_at: nil)
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
end
