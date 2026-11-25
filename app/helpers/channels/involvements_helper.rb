module Channels::InvolvementsHelper
  def button_to_change_involvement(channel, involvement, from_sidebar: false)
    button_to channel_involvement_path(channel, involvement: next_involvement_for(channel, involvement:), from_sidebar:),
      method: :put,
      role: "checkbox", aria: { checked: true, labelledby: dom_id(channel, :involvement_label) }, tabindex: 0,
      class: "btn #{involvement}" do
        image_tag("notification-bell-#{involvement}.svg", aria: { hidden: "true" }, size: 20) +
        tag.span(HUMANIZE_INVOLVEMENT[involvement], class: "for-screen-reader", id: dom_id(channel, :involvement_label))
    end
  end

  def involvement_options_for(channel)
    levels = channel.direct? ? DIRECT_INVOLVEMENT_ORDER : SHARED_INVOLVEMENT_ORDER
    levels.map { |level| [ HUMANIZE_INVOLVEMENT[level], level ] }
  end

  private
    HUMANIZE_INVOLVEMENT = {
      "mentions" => "Mentions only",
      "everything" => "All notifications",
      "nothing" => "Notifications muted",
      "invisible" => "Channel hidden"
    }

    SHARED_INVOLVEMENT_ORDER = %w[ mentions everything nothing ]
    DIRECT_INVOLVEMENT_ORDER = %w[ everything nothing ]

    def next_involvement_for(channel, involvement:)
      order = channel.direct? ? DIRECT_INVOLVEMENT_ORDER : SHARED_INVOLVEMENT_ORDER
      order[(order.index(involvement) || 0) + 1] || order.first
    end
end
