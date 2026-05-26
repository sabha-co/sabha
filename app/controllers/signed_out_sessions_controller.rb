class SignedOutSessionsController < ApplicationController
  layout "session"

  require_unauthenticated_access

  def show
  end
end
