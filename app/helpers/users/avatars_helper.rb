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
    options[:loading] ||= :lazy
    # All avatar rendering goes through the controller which handles:
    # 1. Uploaded avatars
    # 2. Cached DiceBear avatars
    # 3. Live DiceBear API
    # 4. Initials fallback
    image_tag user_image_path(user), aria: { hidden: "true" }, **options
  end

  def user_image_path(user)
    # External avatar URL takes precedence (e.g., from OAuth)
    return user.avatar_url if user.avatar_url.present?

    # Everything else goes through the avatar controller which handles
    # caching and progressive fallback (uploaded → dicebear → initials)
    fresh_user_avatar_path(user)
  end
end
