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

  def social_links_for(user)
    links = []
    links << { url: user.twitter_url, icon: "social/twitter.svg", title: "Twitter" } if user.twitter_url.present?
    links << { url: user.linkedin_url, icon: "social/linkedin.svg", title: "LinkedIn" } if user.linkedin_url.present?
    links << { url: user.personal_url, icon: "link.svg", title: friendly_domain(user.personal_url) } if user.personal_url.present?
    links
  end
end
