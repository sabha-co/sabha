module AccountsHelper
  # Mirrors the sidebar header and the SaaS workspace selector: an uploaded logo
  # renders as an image, otherwise we draw the account's initial rather than the
  # generic stock icon the logo route would otherwise serve.
  def account_logo_tag(style: nil)
    link_to root_path do
      tag.figure class: "account-logo avatar #{style}" do
        if Current.account.logo.attached?
          image_tag fresh_account_logo_path, alt: "Account logo", size: 300
        else
          tag.span(Current.account.name.first, class: "account-logo__initial", aria: { hidden: "true" }) +
            tag.span(Current.account.name, class: "for-screen-reader")
        end
      end
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
    "plum"   => "#7B3F8F",
    "teal"   => "#007471",
    "ocean"  => "#0963B5",
    "amber"  => "#8A6000"
  }.freeze

  def accent_swatch_color(accent)
    ACCENT_SWATCH_COLORS.fetch(accent)
  end

  def online_users_count
    count = Membership.online_user_count
    return count if Current.user.invisible? # you asked to be unseen — don't count yourself into "here now" either
    Membership.online?(Current.user) ? count : count + 1 # You're viewing the page, so you're online
  end

  # "Here now" measures workspace vitality — who's connected — not who's
  # available. It deliberately ignores availability, so a Do Not Disturb member
  # is counted here while showing a red dot elsewhere. The tooltip says so, so
  # the number and the dots beside it aren't read as contradicting each other.
  def here_now_label(count, window: "10 minutes")
    tag.span "#{count} here now", title: "Members connected in the last #{window}"
  end
end
