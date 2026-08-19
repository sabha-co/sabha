module User::Role
  extend ActiveSupport::Concern

  included do
    enum :role, { member: 0, moderator: 1, administrator: 2, bot: 3 }
  end

  def can_administer?(record = nil)
    administrator? || self == record&.creator || record&.new_record?
  end

  def can_manage_account?
    administrator?
  end

  def can_moderate?
    staff?
  end

  def staff?
    moderator? || administrator?
  end

  def can_delete_message?(message)
    can_moderate? || message.creator == self
  end

  def can_edit_message?(message)
    can_moderate? || message.creator == self
  end

  def person?
    !bot?
  end

  def manageable_by?(admin)
    admin.can_administer? && active? && person?
  end

  def removable_by?(admin)
    admin.can_administer? && active? && admin != self
  end

  def bannable_by?(admin)
    admin.can_administer? && admin != self && !banned?
  end

  def unbannable_by?(admin)
    admin.can_administer? && admin != self && banned?
  end

  def reactivatable_by?(admin)
    admin.can_administer? && deactivated?
  end

  def can_create_direct_messages?
    administrator? || !Account.sole.settings.restrict_direct_messages_to_administrators?
  end
end
