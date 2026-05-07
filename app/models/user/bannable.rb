module User::Bannable
  extend ActiveSupport::Concern

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
    sync_workspace_membership_active(true)
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
end
