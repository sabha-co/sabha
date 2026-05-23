# Soft deletion via an `active` boolean column. Used by Message, Room, and Membership.
#
# Provides two named scopes (`active`, `inactive`) and four lifecycle methods.
# There is no `default_scope` — `Message.where(...)` returns all rows, active or
# inactive. The `-> { active }` filter only applies when going through an
# association (e.g. `user.messages`).
#
# Reactivation is programmatic, not console-only: `User#reactivate`,
# `Room#reactivate`, the admin reactivations route, and the SaaS workspace
# re-admit flow all rely on it.
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
