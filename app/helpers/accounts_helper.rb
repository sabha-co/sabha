module AccountsHelper
  def account_logo_tag(style: nil)
    link_to root_path do
      tag.figure image_tag(fresh_account_logo_path, alt: "Account logo", size: 300), class: "account-logo avatar #{style}"
    end
  end

  # The stored value is validated on write; presence_in guards legacy rows
  # that may carry a retired accent name.
  def account_accent
    Current.account&.settings&.accent.presence_in(Account::ACCENTS) || "indigo"
  end

  # Swatch dots always show the light-mode accent, like paint chips — these
  # hexes mirror the --lch-accent light triples in colors.css.
  ACCENT_SWATCH_COLORS = {
    "indigo" => "#4F52D9",
    "ink"    => "#2F3542",
    "forest" => "#1F6F52",
    "rust"   => "#A64B28",
    "plum"   => "#7B3F8F"
  }.freeze

  def accent_swatch_color(accent)
    ACCENT_SWATCH_COLORS.fetch(accent)
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
