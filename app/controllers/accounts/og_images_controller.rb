class Accounts::OgImagesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    if stale?(etag: Current.account)
      expires_in 1.hour, public: true, stale_while_revalidate: 1.week
      send_data Account::OgImage.new(Current.account).png, type: "image/png", disposition: :inline
    end
  end
end
