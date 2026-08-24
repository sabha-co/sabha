# How a presence dot reads. User::Presence decides *which* dot someone gets;
# everything here is what that looks like on a page — the colour it takes, the
# word that goes with it, and where it's allowed to sit.
module PresencesHelper
  # Manual presence and inferred idleness share the amber dot on purpose: the
  # distinction between "I said I'm away" and "you stopped typing" is ours to
  # act on, not something a reader of the dot needs to arbitrate.
  DOT_CLASSES = {
    active:  "status--active",
    idle:    "status--away",
    away:    "status--away",
    dnd:     "status--dnd",
    offline: "status--offline"
  }.freeze

  DOT_LABELS = {
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
  DOT_SURFACES = {
    sidebar:       "sidebar__me-dot",
    direct:        "direct__presence",
    conversation:  "dm-conversation__presence",
    nav:           "navbar-dm__dot",
    member:        "member-row__dot",
    participant:   "status-dot--inline",
    quick_profile: "quick-profile__dot",
    profile_hero:  "profile-hero__dot"
  }.freeze

  # Surfaces that also spell the state out in words. There the dot is decoration
  # and stays out of the accessibility tree — announcing both would say the same
  # thing twice — and the words need replacing on a broadcast alongside it, or
  # they'd sit there contradicting the colour until the next full page load.
  LABELLED_SURFACES = %i[ sidebar nav member participant profile_hero ].freeze

  # The two labels that carry their own styling; the rest are bare text inside a
  # container that already has it.
  LABEL_CLASSES = { sidebar: "sidebar__me-status", nav: "navbar-dm__status" }.freeze

  # What each choosable state looks like when nothing is second-guessing it —
  # the picker shows intent, not the resolved dot, so "Available" stays green
  # there even while the person reading it has already gone idle.
  AVAILABILITY_DOTS = { "available" => :active, "away" => :away, "do_not_disturb" => :dnd }.freeze

  def presence_surfaces
    DOT_SURFACES.keys
  end

  def presence_labelled?(surface)
    LABELLED_SURFACES.include?(surface)
  end

  def presence_dot_class(dot)
    DOT_CLASSES[dot]
  end

  def presence_dot_label(dot)
    DOT_LABELS[dot]
  end

  def availability_dot(state)
    AVAILABILITY_DOTS.fetch(state)
  end

  def presence_dot_id(user, surface)
    dom_id user, "presence_dot_#{surface}"
  end

  def presence_label_id(user, surface)
    dom_id user, "presence_label_#{surface}"
  end

  # Renders nothing at all when the dot is nil (deactivated/banned), so their
  # status chip stays the only claim made about them.
  def presence_dot_tag(user, dot, surface:)
    return if dot.nil?

    labelled = presence_labelled?(surface)

    tag.span id: presence_dot_id(user, surface),
             class: [ "status-dot", presence_dot_class(dot), DOT_SURFACES.fetch(surface) ],
             role: ("img" unless labelled),
             aria: labelled ? { hidden: true } : { label: "#{user.name} is #{presence_dot_label(dot).downcase}" }
  end

  def presence_label_tag(user, dot, surface:)
    return if dot.nil?

    tag.span presence_dot_label(dot), id: presence_label_id(user, surface), class: LABEL_CLASSES[surface]
  end
end
