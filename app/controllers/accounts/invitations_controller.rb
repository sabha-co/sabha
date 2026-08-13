class Accounts::InvitationsController < ApplicationController
  before_action :ensure_can_administer

  def show
    @account = Current.account
  end
end
