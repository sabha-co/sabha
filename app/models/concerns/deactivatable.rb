# frozen_string_literal: true

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
