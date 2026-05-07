module User::Bannable
  extend ActiveSupport::Concern

  included do
    after_update_commit :send_ban_email,   if: :ban_just_happened?
    after_update_commit :send_unban_email, if: :unban_just_happened?
  end

  def ban
    transaction do
      create_bans_from_sessions
      apply_ban
      banned!
    end
  end

  def unban
    transaction do
      bans.delete_all
      active!
    end
  end

  def remove_banned_content_later
    RemoveBannedContentJob.perform_later(self)
  end

  def remove_banned_content
    # Query messages before deactivating (association is scoped to active)
    messages_to_remove = messages.includes(:room).to_a

    # Batch update for deactivation
    Message.where(id: messages_to_remove.map(&:id)).update_all(active: false)

    # Broadcast removals
    messages_to_remove.each(&:broadcast_remove)
  end

  private
    def create_bans_from_sessions
      sessions.pluck(:ip_address).compact_blank.uniq.each do |ip|
        bans.find_or_create_by(ip_address: ip)
      end
    end

    def apply_ban
      revoke_access
      remove_banned_content_later
    end

    def send_ban_email
      UserMailer.banned(self).deliver_later
    end

    def send_unban_email
      UserMailer.unbanned(self).deliver_later
    end

    def ban_just_happened?
      saved_change_to_status? && banned? && notifiable_about_status?
    end

    def unban_just_happened?
      return false unless saved_change_to_status? && notifiable_about_status?
      saved_change_to_status.first == "banned" && active?
    end

    def notifiable_about_status?
      !bot? && email_address.present?
    end
end
