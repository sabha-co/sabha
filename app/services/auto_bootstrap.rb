class AutoBootstrap
  LOCK_FILE = "tmp/auto_bootstrap.lock"

  def self.enabled?
    ENV["AUTO_BOOTSTRAP"] == "true" &&
      ENV["ADMIN_EMAIL"].present? &&
      ENV["ADMIN_PASSWORD"].present?
  end

  def self.should_run?
    enabled? && Account.none?
  end

  def self.run!
    return false unless should_run?

    with_lock do
      # Re-check after acquiring exclusive lock
      return false if Account.any?

      Rails.logger.info "[AutoBootstrap] Creating admin account from environment variables..."

      admin = FirstRun.create!(
        name: ENV.fetch("ADMIN_NAME", "Administrator"),
        email_address: ENV["ADMIN_EMAIL"],
        password: ENV["ADMIN_PASSWORD"]
      )

      # Mark the admin as needing to change their password and pre-verify email
      admin.update!(must_change_password: true, verified_at: Time.current)

      Rails.logger.info "[AutoBootstrap] Admin account created for #{admin.email_address}"

      admin
    end
  rescue => e
    Rails.logger.error "[AutoBootstrap] Failed to create admin: #{e.message}"
    raise
  end

  # File-based exclusive lock for SQLite single-server deployments
  # Blocks until lock acquired, ensuring only one process can bootstrap
  def self.with_lock(&block)
    lock_path = Rails.root.join(LOCK_FILE)
    FileUtils.mkdir_p(lock_path.dirname)

    File.open(lock_path, File::RDWR | File::CREAT, 0644) do |f|
      f.flock(File::LOCK_EX)  # Block until exclusive lock acquired
      yield
    end
  end
end
