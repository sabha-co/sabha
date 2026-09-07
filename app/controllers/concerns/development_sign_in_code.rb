module DevelopmentSignInCode
  private
    def show_development_sign_in_code(code)
      if Rails.env.development?
        flash[:development_sign_in_code] = code
        headers["X-Sign-In-Code"] = code
      end
    end
end
