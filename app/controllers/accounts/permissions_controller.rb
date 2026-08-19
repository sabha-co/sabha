class Accounts::PermissionsController < ApplicationController
  before_action :ensure_can_manage_account

  def show
    @account = Current.account
  end
end
