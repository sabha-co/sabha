module ApplicationHelper
  include RoomsHelper

  def page_title_tag
    tag.title page_title
  end

  def page_title
    parts = [ @page_title, Branding.contextual_app_name ].compact.uniq
    parts.join(" | ")
  end

  def current_user_meta_tags
    unless Current.user.nil?
      safe_join [
        tag(:meta, name: "current-user-id", content: Current.user.id),
        tag(:meta, name: "current-user-name", content: Current.user.name),
        tag(:meta, name: "current-user-role", content: Current.user.role),
        tag(:meta, name: "current-user-avatar-url", content: user_image_path(Current.user))
      ]
    end
  end

  # Emits the cable URL with a signed JWT identity so anycable-go can identify
  # the socket in Go and skip the Rails connect RPC. The token is minted from
  # the already-authenticated request, so a reconnect storm no longer hits the
  # RPC. With no current user (login pages) we fall back to a tokenless URL so
  # anycable-go authenticates via the connect RPC.
  def signed_action_cable_meta_tag
    return action_cable_meta_tag if Current.user.nil?

    base_url = ActionCable.server.config.url || ActionCable.server.config.mount_path
    token = AnyCable::JWT.encode({ current_user: Current.user })
    tag "meta", name: "action-cable-url", content: "#{base_url}?#{AnyCable.config.jwt_param}=#{token}"
  end

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  # Chip label: the glyph leads ("✦ STEWARD"); icon-less badges stay name-only.
  def badge_label(badge)
    [ badge.icon.presence, badge.name ].compact.join(" ")
  end

  def badge_tag(badge, class_name: "member-badge")
    tag.span badge_label(badge), class: class_name, style: "--badge-color: #{badge.color}"
  end

  def badge_holders_summary(badge)
    count = badge.users.count
    count.zero? ? "No one yet" : pluralize(count, "person")
  end

  def badge_deletion_impact(badge)
    case badge.users.length
    when 0 then "No one has it, so nothing else changes."
    when 1 then "One person has it — they keep their role, they just lose the chip."
    else "#{badge.users.length} people have it — they keep their roles, they just lose the chip."
    end
  end

  def body_classes
    [ @body_class, admin_body_class, staff_body_class, account_logo_body_class, workspace_selector_body_class, workspace_banner_body_class ].compact.join(" ")
  end

  def link_back
    if params[:from].present?
      link_back_to params[:from]
    else
      link_back_to_last_room_visited
    end
  end

  def link_back_to_or_referrer(default_path)
    link_back_to(params[:from].presence || referrer_back_path || default_path)
  end

  def link_home
    link_back_to request.referer || "/"
  end

  def link_back_to(destination, label: "Back")
    link_to destination, class: "navbar-back d-hotwire-native-none" do
      tag.span("‹", class: "navbar-back__chevron", aria: { hidden: true }) +
        tag.span(label, class: "navbar-back__label")
    end
  end

  def umami_analytics_tag
    return unless Rails.env.production? && Branding.umami_website_id.present?

    tag.script(defer: true, "data-website-id": Branding.umami_website_id, src: "https://#{Branding.umami_host}/script.js")
  end

  private
    def admin_body_class
      "admin" if Current.user&.can_administer?
    end

    # Gates staff-only affordances (e.g. the pinned-strip unpin / message Pin
    # control) in CSS, since Turbo broadcasts render those partials viewer-less.
    def staff_body_class
      "staff" if Current.user&.staff?
    end

    def account_logo_body_class
      "account-has-logo" if Current.account&.logo&.attached?
    end

    def workspace_selector_body_class
      # SaaS mode: show_workspace_selector? is defined in WorkspaceSelectorHelper
      # Single-tenant mode: returns nil (no workspace selector)
      "app-with-workspaces" if respond_to?(:show_workspace_selector?) && show_workspace_selector?
    end

    def workspace_banner_body_class
      "has-workspace-banner" if Sabha.saas? && Current.workspace.present?
    end

    # Extracts a back path from the referer if it matches a known inbox/search page.
    # Returns nil for room pages or unrecognized paths so callers fall back to defaults.
    # Preserves query string for search pages and handles SaaS workspace path prefixes.
    def referrer_back_path
      return unless request.referer.present?

      uri = URI.parse(request.referer)
      path = uri.path

      # Strip SaaS workspace prefix (SCRIPT_NAME) from referrer path
      prefix = request.script_name
      path = path.delete_prefix(prefix) if prefix.present?

      if path.match?(%r{\A/inbox/|/searches|/users/\d+/messages})
        query = uri.query
        query.present? ? "#{prefix}#{path}?#{query}" : "#{prefix}#{path}"
      end
    rescue URI::InvalidURIError
      nil
    end
end
