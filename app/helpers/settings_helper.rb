module SettingsHelper
  def personal_settings_sections
    [
      [ :profile, "Profile", user_profile_path ],
      [ :appearance, "Appearance", user_appearance_path ],
      [ :notifications, "Notifications", edit_user_notification_settings_path ],
      [ :account_data, "Account & data", user_account_data_path ]
    ]
  end

  def community_settings_sections
    [
      [ :identity, "Identity", edit_account_path ],
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
