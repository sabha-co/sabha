require "zlib"

module Users::AvatarsHelper
  AVATAR_COLORS = %w[
    #AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E #D07B53
    #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F #3B3633 #67695E
  ]

  def avatar_background_color(user)
    AVATAR_COLORS[Zlib.crc32(user.to_param) % AVATAR_COLORS.size]
  end

  def avatar_link_tag(user, **options)
    link_to user_path(user), title: user.title, class: "btn avatar", data: { turbo_frame: "_top" } do
      avatar_image_tag(user, size: 48, **options)
    end
  end

  def avatar_tag(user, **options)
    tag.span(title: user.title, class: "btn avatar") do
      avatar_image_tag(user, size: 48, **options)
    end
  end

  def avatar_image_tag(user, **options)
    if user.avatar.attached? || user.avatar_url.present? || user.bot?
      options[:loading] ||= :lazy
      image_tag user_image_path(user), aria: { hidden: "true" }, **options
    else
      avatar_monogram_tag(user)
    end
  end

  def avatar_monogram_tag(user)
    initials = user.name.split.map(&:first).first(2).join.upcase
    color_index = Zlib.crc32(user.to_param) % AVATAR_COLORS.size

    tag.div(
      initials,
      class: "avatar-monogram avatar-monogram--#{color_index}",
      "aria-label": user.name,
      title: user.title,
    )
  end

  def user_image_path(user)
    if user.avatar.attached?
      fresh_user_avatar_path(user)
    elsif user.avatar_url.present?
      user.avatar_url
    elsif user.bot?
      asset_path("default-bot-avatar.svg")
    else
      initials = render template: "users/avatars/show", formats: [ :svg ], locals: { user: user }
      "data:image/svg+xml,#{svg_to_uri(initials)}"
    end
  end

  def svg_to_uri(svg)
    # Remove comments, xml meta, and doctype
    svg = svg.gsub(/<!--.*?-->|<\?.*?\?>|<!.*?>/m, "").gsub(/\s+/, " ").gsub("> <", "><").gsub(/([\w:])="(.*?)"/, "\\1='\\2'").strip
    svg = Rack::Utils.escape(svg)
    # Un-escape characters in the given URI-escaped string that do not need escaping in "-quoted data URIs
    svg = svg.gsub("%3D", "=").gsub("%3A", ":").gsub("%2F", "/").gsub("%27", "'").tr("+", " ")
  end
end
