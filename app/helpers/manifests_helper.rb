module ManifestsHelper
  # Where a client sends someone to sign in: the same entry point a signed-out
  # browser is redirected to.
  def sign_in_entry_path
    if !Sabha.saas? && (Account.sso_auth? || FirstRun.should_auto_bootstrap?)
      sso_handshake_path
    else
      new_session_path
    end
  end
end
