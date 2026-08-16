module UsersHelper
  def link_to_direct_room_with(user)
    link_to new_rooms_direct_path(user_ids: [ user.id ]), class: "btn btn--primary full-width txt--large", data: { turbo_frame: "_top" } do
      image_tag("messages.svg")
    end
  end

  def streak_icon(streak)
    case streak
    when 0..1 then "💤"
    when 2..6 then "✨"
    when 7..13 then "⚡"
    when 14..29 then "💪"
    else "🔥"
    end
  end

  def social_link_tag(url:, icon:, title:)
    return if url.blank?

    link_to with_protocol(url), target: "_blank", class: "social-link", title: title do
      image_tag(icon, aria: { hidden: true }) +
      content_tag(:span, title, class: "for-screen-reader")
    end
  end
end
