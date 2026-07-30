class Users::AvatarsController < ApplicationController
  include ActiveStorage::Streaming
  allow_unauthenticated_access only: :show

  rescue_from(ActiveSupport::MessageVerifier::InvalidSignature) { head :not_found }
  rescue_from("ActiveRecord::Tenanted::NoTenantError") { head :not_found } if Sabha.saas?

  def show
    # Skip session cookies for avatar requests
    request.session_options[:skip] = true

    @user = User.from_avatar_token(params[:user_id])

    if stale?(etag: @user)
      expires_in 30.minutes, public: true, stale_while_revalidate: 1.week

      if (avatar_variant = @user.avatar_variant)
        send_webp_blob_file avatar_variant.key
      elsif @user.bot?
        render_bot
      elsif Dicebear.enabled?
        serve_dicebear_avatar
      else
        render_initials
      end
    end
  end

  def destroy
    Current.user.avatar.purge
    redirect_to user_profile_url
  end

  private
    def serve_dicebear_avatar
      svg = @user.dicebear_svg
      if svg.present?
        response.headers["Content-Security-Policy"] = "script-src 'none'; object-src 'none'"
        send_data svg, type: "image/svg+xml", disposition: :inline
      else
        render_initials
      end
    end

    def send_webp_blob_file(key)
      send_file ActiveStorage::Blob.service.path_for(key), content_type: "image/webp", disposition: :inline
    end

    def render_bot
      if Dicebear.enabled?
        serve_dicebear_avatar
      else
        send_file Rails.root.join("app/assets/images/default-bot-avatar.svg"), content_type: "image/svg+xml", disposition: :inline
      end
    end

    def render_initials
      render formats: :svg
    end
end
