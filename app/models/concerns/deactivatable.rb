# frozen_string_literal: true

# Soft deletion via an `active` boolean column. Used by Message, Room, and Membership.
#
# Note: There is no UI to undo deletion for Rooms or Messages — deactivation is
# one-way from the user's perspective. This was inherited from the Small Bets fork
# and is likely intended for manual reversion via Rails console. Keeping as-is for now.
module Deactivatable
  extend ActiveSupport::Concern

  included do
    scope :active,   -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
  end

  def deactivate!
    self.active = false
    save!
  end

  def deactivate(validate: true)
    self.active = false
    save(validate:)
  end

  def activate!
    self.active = true
    save!
  end

  def activate
    self.active = true
    save
  end

  def deactivated?
    !active?
  end
end
