module Authorization
  private
    def ensure_can_administer
      redirect_to root_path unless Current.user.can_administer?
    end
end
