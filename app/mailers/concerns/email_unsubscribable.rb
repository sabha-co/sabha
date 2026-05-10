# Mints unsubscribe tokens and emits RFC 8058 List-Unsubscribe headers for
# notification emails. The token carries the tenant — the unsubscribe URL
# never includes a workspace prefix, which is what lets a click from any
# inbox land on the right workspace's settings.
module EmailUnsubscribable
  extend ActiveSupport::Concern

  VALID_SURFACES = %i[ missed_notifications weekly_digest ].freeze

  private
    def mint_unsubscribe_token(user, surface)
      raise ArgumentError, "unknown surface #{surface.inspect}" unless VALID_SURFACES.include?(surface.to_sym)

      payload = {
        user_id: user.id,
        tenant:  current_tenant_for_token,
        surface: surface.to_sym
      }
      Rails.application.message_verifier(:email_unsubscribe).generate(payload)
    end

    def unsubscribe_url_for(user, surface)
      email_unsubscribe_url(token: mint_unsubscribe_token(user, surface))
    end

    # RFC 8058 (one-click) requires both List-Unsubscribe and List-Unsubscribe-Post.
    # Most inbox providers honor the POST variant; both are included for compatibility.
    def unsubscribe_headers(user, surface)
      url = unsubscribe_url_for(user, surface)
      {
        "List-Unsubscribe"      => "<#{url}>",
        "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
      }
    end

    def workspace_name
      Account.sole&.name || Branding.contextual_app_name
    end

    def current_tenant_for_token
      ApplicationRecord.current_tenant if defined?(ActiveRecord::Tenanted) && Sabha.saas?
    end
end
