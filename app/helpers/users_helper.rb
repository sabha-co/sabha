module UsersHelper
  RANK_MEDALS = { 1 => "🥇", 2 => "🥈", 3 => "🥉" }.freeze

  def button_to_direct_room_with(user)
    button_to rooms_directs_path(user_ids: [ user.id ]), class: "btn btn--primary full-width txt--large" do
      image_tag("messages.svg")
    end
  end

  def rank_medal(rank)
    RANK_MEDALS[rank]
  end

  def social_link_tag(url:, icon:, title:)
    return if url.blank?

    link_to with_protocol(url), target: "_blank", class: "social-link", title: title do
      image_tag(icon, aria: { hidden: true }) +
      content_tag(:span, title, class: "for-screen-reader")
    end
  end
end
