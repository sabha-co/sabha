module Authorization
  private
    def ensure_can_administer
      redirect_to root_path unless Current.user.can_administer?
    end

    def ensure_can_manage_account
      return if Current.user.can_manage_account?

      render_forbidden \
        title: "Administrators only",
        message: "Community settings are limited to administrators. Ask an administrator if you need a change.",
        back_to: account_path,
        back_label: "Back to community settings"
    end

    # A 403 a human reaches by navigating — a stale or disabled link — gets a
    # styled, in-app page that explains the wall and offers a way back. Every
    # other 403 stays a bare status, which is what those callers expect: form
    # posts, turbo-frame loads, and API/machine clients all fall through here.
    def render_forbidden(title: "You don't have access",
                         message: "This page isn't available to your account. If you think that's a mistake, ask an administrator.",
                         back_to: root_path, back_label: "Back home")
      if request.get? && request.format.html? && request.headers["Turbo-Frame"].blank?
        render "errors/forbidden", status: :forbidden, layout: "application",
               locals: { title:, message:, back_to:, back_label: }
      else
        head :forbidden
      end
    end
end
