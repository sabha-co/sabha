# FirstRun handles initial account and admin user creation.
#
# There are two ways to set up a new Campfire instance:
#
# 1. MANUAL FIRST-RUN (Default for Kamal/self-hosted deployments)
#    - First visitor to the site sees a setup form
#    - They enter their name, email, and password to become admin
#    - Uses FirstRun.create! directly from FirstRunsController
#
# 2. AUTO-BOOTSTRAP (Campfire Cloud managed deployments only)
#    - Headless setup without user interaction
#    - Requires ENV vars: AUTO_BOOTSTRAP=true, ADMIN_EMAIL, ADMIN_AUTH_TOKEN
#    - Creates admin account automatically on first request
#    - Sends welcome email with one-time login link
#    - Admin clicks link to authenticate (no password needed)
#    - Subsequent logins use OTP (6-digit code via email)
#
# Auto-bootstrap is designed for managed hosting platforms where:
#    - The hosting platform controls the deployment
#    - Admin credentials are generated programmatically
#    - Users receive a welcome email with a magic link to sign in
#    - No manual setup form is needed
#
class FirstRun
  FIRST_ROOM_NAME = "All Talk"
  LOCK_FILE = "tmp/auto_bootstrap.lock"

  def self.account_name
    Branding.app_name
  end

  # Manual first-run: creates admin from user-submitted form data
  def self.create!(user_params)
    account = Account.create!(name: account_name)
    room    = Rooms::Open.new(name: FIRST_ROOM_NAME)

    administrator = room.creator = User.new(user_params.merge(role: :administrator))
    room.save!

    room.memberships.grant_to administrator

    administrator
  end

  # Check if auto-bootstrap is enabled via environment variables.
  # Requires all three: AUTO_BOOTSTRAP=true, ADMIN_EMAIL, ADMIN_AUTH_TOKEN
  def self.auto_bootstrap_enabled?
    ENV["AUTO_BOOTSTRAP"] == "true" &&
      ENV["ADMIN_EMAIL"].present? &&
      ENV["ADMIN_AUTH_TOKEN"].present?
  end

  # Should we run auto-bootstrap? Only if enabled AND no account exists yet.
  def self.should_auto_bootstrap?
    auto_bootstrap_enabled? && Account.none?
  end

  # Perform auto-bootstrap: create admin account with one-time login token.
  # Called from MarketingController when first visitor hits the site.
  # Returns the admin user if successful, false if already bootstrapped.
  def self.auto_bootstrap!
    return false unless should_auto_bootstrap?

    with_lock do
      return false if Account.any?

      token_value = ENV["ADMIN_AUTH_TOKEN"]
      if token_value.length < 32
        raise ArgumentError, "ADMIN_AUTH_TOKEN must be at least 32 characters for security"
      end

      Rails.logger.info "[AutoBootstrap] Creating admin account for Campfire Cloud..."

      admin = create!(
        name: ENV.fetch("ADMIN_NAME", "Administrator"),
        email_address: ENV["ADMIN_EMAIL"],
        password: SecureRandom.hex(32)  # Random password, never used
      )
      admin.update!(verified_at: Time.current)

      # Create AuthToken for one-time login link
      admin.auth_tokens.create!(
        token: token_value,
        expires_at: 24.hours.from_now
      )

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
