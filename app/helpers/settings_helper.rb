module SettingsHelper
  def personal_settings_sections
    [
      [ :profile, "Profile", user_profile_path ],
      [ :appearance, "Appearance", user_appearance_path ],
      [ :notifications, "Notifications", edit_user_notification_settings_path ],
      *(Current.account.settings.allow_users_to_create_invite_links? ? [ [ :personal_invitations, "Invitations", user_invitations_path ] ] : []),
      [ :account_data, "Account & data", user_account_data_path ]
    ]
  end

  def community_settings_sections
    sections = [
      [ :identity, "Identity", Current.user.can_administer? ? edit_account_path : account_path ],
      [ :members, "Members", account_users_path ]
    ]

    return sections unless Current.user.can_administer?

    sections + [
      [ :invitations, "Invitations", account_invitations_path ],
      [ :badges, "Badges", account_badges_path ],
      [ :permissions, "Permissions", account_permissions_path ],
      [ :bots, "Bots & webhooks", account_bots_path ]
    ]
  end

  def community_settings_section?(section)
    community_settings_sections.any? { |key, _, _| key == section }
  end
end
