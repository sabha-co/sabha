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
        tag(:meta, name: "current-user-role", content: Current.user.role)
      ]
    end
  end

  def custom_styles_tag
    if custom_styles = Current.account&.custom_styles
      # Inline custom styles should not force a full Turbo reload across navigations
      # Sanitize to prevent breaking out of the <style> tag context (XSS via </style><script>...)
      sanitized = custom_styles.to_s.gsub(%r{</style}i, "")
      tag.style(sanitized.html_safe)
    end
  end

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  def body_classes
    [ @body_class, admin_body_class, account_logo_body_class, workspace_selector_body_class, workspace_banner_body_class ].compact.join(" ")
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

  def link_back_to(destination)
    link_to destination, class: "btn d-hotwire-native-none" do
      icon_tag("arrow-left") + tag.span("Go Back", class: "for-screen-reader")
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
