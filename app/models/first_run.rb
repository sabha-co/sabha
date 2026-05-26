# FirstRun handles initial account and admin user creation.
#
# Two ways to set up a new Sabha instance:
#
# 1. MANUAL FIRST-RUN (default for Kamal/self-hosted deployments)
#    First visitor sees a setup form and enters name, email, and password to
#    become admin. Uses FirstRun.create! from FirstRunsController.
#
# 2. SSO AUTO-BOOTSTRAP (Sabha Cloud managed deployments and any operator
#    fronting Sabha with an SSO provider)
#    With AUTO_BOOTSTRAP=true plus SSO_PROVIDER_URL and SSO_SECRET set, the
#    first unauthenticated visit is redirected through the SSO handshake.
#    The callback runs FirstRun.auto_bootstrap_from_sso! to provision the
#    Account, admin User, SSO record, and General room from the payload —
#    no setup form, no emailed magic link.
#
#    After bootstrap the droplet runs under whatever AUTH_METHOD the operator
#    configured (password, otp, or sso). AUTO_BOOTSTRAP is a one-shot ignition
#    mechanism gated by Account.none?, not a persistent auth mode.
#
class FirstRun
  FIRST_ROOM_NAME = "General"
  LOCK_FILE = "tmp/auto_bootstrap.lock"

  def self.account_name
    Branding.app_name
  end

  # Manual first-run: creates admin from user-submitted form data
  def self.create!(user_params)
    account = Account.create!(name: account_name)
    room    = Rooms::Open.new(name: FIRST_ROOM_NAME, auto_join: true)

    administrator = room.creator = User.new(user_params.merge(role: :administrator))
    administrator.validate!
    room.save!

    room.memberships.grant_to administrator

    administrator
  end

  # SSO auto-bootstrap is wired up when AUTO_BOOTSTRAP=true and the SSO
  # provider env is set. Sabha Cloud sets all three on each droplet so the
  # customer's sabha.co identity provisions the first admin on first visit.
  def self.auto_bootstrap_enabled?
    ENV["AUTO_BOOTSTRAP"] == "true" &&
      ENV["SSO_PROVIDER_URL"].present? &&
      ENV["SSO_SECRET"].present?
  end

  def self.should_auto_bootstrap?
    auto_bootstrap_enabled? && Account.none?
  end

  # Provisions the first Account, admin User, SingleSignOnRecord, and the
  # default General room straight from the SSO callback payload. Returns the
  # admin user; returns false if an Account already exists.
  def self.auto_bootstrap_from_sso!(payload)
    return false if Account.any?

    with_lock do
      return false if Account.any?

      Account.create!(name: account_name)
      room = Rooms::Open.new(name: FIRST_ROOM_NAME, auto_join: true)

      admin = room.creator = User.new(
        name: SingleSignOnRecord.name_from(payload),
        email_address: SingleSignOnRecord.email_address_from(payload),
        avatar_url: payload["avatar_url"],
        role: :administrator,
        verified_at: Time.current
      )
      admin.validate!
      room.save!
      room.memberships.grant_to(admin)

      admin.create_single_sign_on_record!(
        external_id: SingleSignOnRecord.external_id_from(payload),
        external_email: SingleSignOnRecord.email_address_from(payload),
        last_payload: payload.to_json,
        last_seen_at: Time.current
      )

      admin
    end
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
