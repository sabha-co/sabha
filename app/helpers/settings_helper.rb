module SettingsHelper
  def personal_settings_sections
    [
      [ :profile, "Profile", user_profile_path ],
      [ :appearance, "Appearance", user_appearance_path ],
      [ :notifications, "Notifications", edit_user_notification_settings_path ],
      *(Current.account.settings.allow_users_to_create_invite_links? ? [ [ :personal_invitations, "Invitations", user_invitations_path ] ] : []),
      [ :account_data, "Account", user_account_data_path ]
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

  # A segmented button group wired to a Stimulus controller — the appearance
  # toggles (theme, density) ride this. Each option is
  # { label:, action:, target:, selected: false }, mapping to controller#action
  # and controller-target; the controller flips aria-selected on connect.
  def segmented_control_tag(controller:, label:, options:)
    tag.div role: "group", class: "segmented-control", aria: { label: label } do
      safe_join(options.map { |option|
        tag.button option[:label], type: "button", class: "segmented-control__btn",
          aria: { selected: option.fetch(:selected, false) },
          data: { action: "#{controller}##{option[:action]}", "#{controller}_target" => option[:target] }
      })
    end
  end
end
