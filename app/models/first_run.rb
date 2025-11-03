class FirstRun
  ACCOUNT_NAME = BrandingConfig.app_name
  FIRST_ROOM_NAME = "All Talk"

  def self.create!(user_params)
    account = Account.create!(name: ACCOUNT_NAME)
    room    = Rooms::Open.new(name: FIRST_ROOM_NAME)

    administrator = room.creator = User.new(user_params.merge(role: :administrator))
    room.save!

    room.memberships.grant_to administrator

    administrator
  end
end
