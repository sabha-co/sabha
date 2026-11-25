# Adds every active user to the channel instead of an invited few — the membership
# behind an open channel's "add all members" toggle and a forum's always-on
# community access (Channels::Forum forces auto_join on and hides the toggle). New
# signups are swept in too, via User#grant_membership_to_auto_join_channels.
module Channel::AutoJoinable
  extend ActiveSupport::Concern

  included do
    after_save_commit :grant_access_to_all_users, if: :auto_join?
  end

  private
    # Grant membership to every active user who lacks one. Guarded so it only runs
    # when the channel just became auto-join — on create, on a type flip into this
    # class, or when the toggle flips on — not on every later save.
    def grant_access_to_all_users
      return unless type_previously_changed?(to: type) || saved_change_to_auto_join?(to: true)

      users_to_add = User.active
                         .joins("LEFT JOIN memberships ON memberships.user_id = users.id AND memberships.channel_id = #{id} AND memberships.active = true")
                         .where("memberships.id IS NULL")

      memberships.grant_to(users_to_add) if users_to_add.exists?
    end
end
