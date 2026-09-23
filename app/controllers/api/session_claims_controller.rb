class API::SessionClaimsController < API::ProtocolController
  allow_unauthenticated_access

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }

  def create
    claim = Session::Claim.redeem!(
      token: params[:token],
      nonce: params[:nonce],
      origin: params[:origin],
      code_verifier: params[:code_verifier]
    )
    start_new_session_for(claim.user)
    render json: { return_path: claim.return_path }
  rescue Session::Claim::Invalid
    render json: { error: "Invalid or expired claim" }, status: :forbidden
  end
end
