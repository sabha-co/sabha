module Membership::Starrable
  extend ActiveSupport::Concern

  included do
    scope :starred,   -> { where(starred: true) }
    scope :unstarred, -> { where(starred: false) }

    validate :starred_only_for_shared_visible_channels, if: :starred?
    before_validation :unstar_if_invisible

    after_update_commit :broadcast_star_change, if: :saved_change_to_starred?
  end

  def sidebar_list_name
    starred? ? :starred_channels : :shared_channels
  end

  private
    def starred_only_for_shared_visible_channels
      if channel.direct? || channel.thread?
        errors.add(:starred, "is not allowed for direct or thread channels")
      end
    end

    # Cascade for Membership#leave! — leaving a channel sets involvement to
    # :invisible, which implies the channel can't show up in the starred sidebar
    # list. This callback keeps that invariant on every involvement write.
    def unstar_if_invisible
      self.starred = false if involved_in_invisible? && starred?
    end

    def broadcast_star_change
      return if involved_in_invisible? || channel.direct? || channel.thread?

      old_list = starred_before_last_save ? :starred_channels : :shared_channels

      Turbo::StreamsChannel.broadcast_remove_to(
        user, :channels,
        target: [ channel, "#{old_list}_list_node" ]
      )

      Turbo::StreamsChannel.broadcast_append_to(
        user, :channels,
        target: sidebar_list_name,
        partial: "users/sidebars/channels/shared",
        locals: { list_name: sidebar_list_name, membership: self },
        attributes: { maintain_scroll: true }
      )
    end
end
