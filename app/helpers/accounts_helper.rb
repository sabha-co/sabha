module AccountsHelper
  def account_logo_tag(style: nil)
    link_to root_path do
      tag.figure image_tag(fresh_account_logo_path, alt: "Account logo", size: 300), class: "account-logo avatar #{style}"
    end
  end

  def online_users_count
    count = Membership.online_user_count
    Membership.online?(Current.user) ? count : count + 1 # You're viewing the page, so you're online
  end

  STATUS_CSS_CLASSES = { active: "status--active", away: "status--away", offline: "status--offline" }.freeze

  def activity_status_class(user)
    status = @activity_statuses&.dig(user.id) || :offline
    STATUS_CSS_CLASSES[status]
  end

  def online_status_class(user)
    status = @activity_statuses&.dig(user.id)
    STATUS_CSS_CLASSES[status] unless status.nil? || status == :offline
  end

  def badge_options
    badges = @badges || Badge.ordered
    [ [ "No badge", "" ] ] + badges.map { |b| [ b.name, b.id ] }
  end
end
