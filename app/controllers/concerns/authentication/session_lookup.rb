module Authentication::SessionLookup
  def find_session_by_cookie
    if Sabha.saas?
      find_global_session_by_cookie
    else
      find_local_session_by_cookie
    end
  end

  private

  def find_global_session_by_cookie
    token = cookies.signed[:global_session_token]
    return unless token

    GlobalSession.find_by(token: token)
  end

  def find_local_session_by_cookie
    token = cookies.signed[:session_token]
    return unless token

    Session.find_by(token: token)
  end
end
