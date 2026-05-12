# Public, token-authenticated unsubscribe. The signed token carries the
# tenant — there is no path-based workspace prefix, so a click from any inbox
# lands on the right workspace's settings.
#
# POST is the RFC 8058 one-click target invoked by mail clients without the
# user opening the page; GET shows a confirmation. Both are idempotent.
class EmailUnsubscribesController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :create
  rate_limit to: 30, within: 1.minute, with: -> { render :invalid, status: :too_many_requests }

  def show
    @payload = decode_token(params[:token]) or return render(:invalid, status: :not_found)
  end

  def create
    payload = decode_token(params[:token]) or return render(:invalid, status: :not_found)
    @surface = payload[:surface]
    found = with_tenant_from(payload[:tenant]) do
      user = User.find_by(id: payload[:user_id]) or next false
      user.unsubscribe_from_email!(@surface)
      true
    end
    render :invalid, status: :not_found unless found
  end

  private
    def decode_token(token)
      payload = Rails.application.message_verifier(:email_unsubscribe).verify(token).symbolize_keys
      return nil unless EmailUnsubscribable::VALID_SURFACES.include?(payload[:surface]&.to_sym)
      payload[:surface] = payload[:surface].to_sym
      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage, NoMethodError, TypeError
      nil
    end

    # The token, not the request path, is authoritative for tenant resolution.
    # `prohibit_shard_swapping: false` allows entering the token's tenant even
    # if the request somehow already had a tenant context.
    def with_tenant_from(tenant, &block)
      if defined?(ActiveRecord::Tenanted) && Sabha.saas? && tenant.present?
        ApplicationRecord.with_tenant(tenant, prohibit_shard_swapping: false, &block)
      else
        block.call
      end
    end
end
