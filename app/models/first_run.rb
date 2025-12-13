class FirstRun
  ACCOUNT_NAME = BrandingConfig.app_name
  FIRST_ROOM_NAME = "All Talk"
  LOCK_FILE = "tmp/auto_bootstrap.lock"

  def self.create!(user_params)
    account = Account.create!(name: ACCOUNT_NAME)
    room    = Rooms::Open.new(name: FIRST_ROOM_NAME)

    administrator = room.creator = User.new(user_params.merge(role: :administrator))
    room.save!

    room.memberships.grant_to administrator

    administrator
  end

  # Auto-bootstrap: headless setup from environment variables
  def self.auto_bootstrap_enabled?
    ENV["AUTO_BOOTSTRAP"] == "true" &&
      ENV["ADMIN_EMAIL"].present? &&
      ENV["ADMIN_PASSWORD"].present?
  end

  def self.should_auto_bootstrap?
    auto_bootstrap_enabled? && Account.none?
  end

  def self.auto_bootstrap!
    return false unless should_auto_bootstrap?

    with_lock do
      return false if Account.any?

      Rails.logger.info "[AutoBootstrap] Creating admin account from environment variables..."

      admin = create!(
        name: ENV.fetch("ADMIN_NAME", "Administrator"),
        email_address: ENV["ADMIN_EMAIL"],
        password: ENV["ADMIN_PASSWORD"]
      )

      admin.update!(must_change_password: true, verified_at: Time.current)

      Rails.logger.info "[AutoBootstrap] Admin account created for #{admin.email_address}"

      admin
    end
  rescue => e
    Rails.logger.error "[AutoBootstrap] Failed to create admin: #{e.message}"
    raise
  end

  def self.with_lock(&block)
    lock_path = Rails.root.join(LOCK_FILE)
    FileUtils.mkdir_p(lock_path.dirname)

    File.open(lock_path, File::RDWR | File::CREAT, 0644) do |f|
      f.flock(File::LOCK_EX)
      yield
    end
  end
end
