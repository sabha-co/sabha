module Room::Announceable
  extend ActiveSupport::Concern

  included do
    after_create_commit :announce_creation
  end

  def announce_membership_changes(granted: [], revoked: [], actor:)
    if granted.present?
      post_system_message(event: "member_joined", body: membership_change_text("added", granted), actor: actor)
    end
    if revoked.present?
      post_system_message(event: "member_left", body: membership_change_text("removed", revoked), actor: actor)
    end
  end

  def announce_rename(old_name, actor:)
    post_system_message(event: "room_renamed", body: "renamed the room from #{old_name} to #{name}", actor: actor)
  end

  private
    def announce_creation
      return if direct? || thread? || post?
      return unless User.active.where.not(id: creator_id).exists? # No audience on fresh setup
      post_system_message(event: "room_created", body: "created the room", actor: creator)
    end

    def membership_change_text(verb, users)
      if users.size <= 2
        "#{verb} #{users.map(&:name).to_sentence}"
      else
        "#{verb} #{users.size} members"
      end
    end
end
