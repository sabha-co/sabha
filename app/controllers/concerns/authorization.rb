module Authorization
  private
    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?
    end
end
