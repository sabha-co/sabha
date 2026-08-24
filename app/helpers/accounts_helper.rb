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

  # Manual presence and inferred idleness share the amber dot on purpose: the
  # distinction between "I said I'm away" and "you stopped typing" is ours to
  # act on, not something a reader of the dot needs to arbitrate.
  PRESENCE_DOT_CSS_CLASSES = {
    active:  "status--active",
    idle:    "status--away",
    away:    "status--away",
    dnd:     "status--dnd",
    offline: "status--offline"
  }.freeze

  PRESENCE_DOT_LABELS = {
    active:  "Available",
    idle:    "Away",
    away:    "Away",
    dnd:     "Do not disturb",
    offline: "Offline"
  }.freeze

  # Every place a dot can appear, and the class that positions it there. The
  # subject's broadcast replays this whole list because the server has no idea
  # which of these the viewer happens to have on screen — Turbo drops the actions
  # whose target isn't present. Holding the positioning class here is what lets a
  # rebroadcast dot land in the sidebar footer or a directory row without either
  # one being flattened into a single shared shape.
  PRESENCE_DOT_SURFACES = {
    sidebar:       "sidebar__me-dot",
    direct:        "direct__presence",
    conversation:  "dm-conversation__presence",
    nav:           "navbar-dm__dot",
    member:        "member-row__dot",
    participant:   "status-dot--inline",
    quick_profile: "quick-profile__dot",
    profile_hero:  "profile-hero__dot"
  }.freeze

  # What each choosable state looks like when nothing is second-guessing it —
  # the picker shows intent, not the resolved dot, so "Available" stays green
  # there even while the person reading it has already gone idle.
  PRESENCE_STATE_DOTS = { "available" => :active, "away" => :away, "do_not_disturb" => :dnd }.freeze

  def presence_dot_class(dot)
    PRESENCE_DOT_CSS_CLASSES[dot]
  end

  def presence_dot_label(dot)
    PRESENCE_DOT_LABELS[dot]
  end

  def presence_dot_id(user, surface)
    dom_id user, "presence_dot_#{surface}"
  end


  # Renders nothing at all when the dot is nil (deactivated/banned), so their
  # status chip stays the only claim made about them.
  def presence_dot_tag(user, dot, surface:)
    return if dot.nil?

    tag.span id: presence_dot_id(user, surface),
             class: [ "status-dot", presence_dot_class(dot), PRESENCE_DOT_SURFACES.fetch(surface) ],
             aria: { label: "#{user.name} is #{presence_dot_label(dot).downcase}" },
             role: "img"
  end
end
