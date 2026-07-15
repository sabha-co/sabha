require "test_helper"

# Guards the AnyCable-required cutover. The in-process ActionCable fallback and
# its ANYCABLE_ENABLED / AnyCable::Rails.enabled? branches were removed; if any
# creep back, real-time silently regresses to the unsupported fallback path.
class AnycableRequiredTest < ActiveSupport::TestCase
  ROOT = Rails.root

  test "no AnyCable::Rails.enabled? gate remains in app/ (whisper is unconditional)" do
    offenders = Dir.glob(ROOT.join("app/**/*.{rb,erb}")).select do |path|
      File.read(path).include?("AnyCable::Rails.enabled?")
    end

    assert_empty offenders,
      "AnyCable is required — remove the AnyCable::Rails.enabled? branches: #{offenders}"
  end

  test "no ANYCABLE_ENABLED reference remains in configs, env samples, or the deploy workflow" do
    files = %w[
      config/cable.yml
      config/anycable.yml
      config/environments/development.rb
      config/deploy.yml
      config/deploy.multitenant.yml
      .env.sample
      .env.multitenant.sample
      .github/workflows/deploy_with_kamal.yml
      bin/dev
    ]

    offenders = files.select do |rel|
      path = ROOT.join(rel)
      File.exist?(path) && File.read(path).include?("ANYCABLE_ENABLED")
    end

    assert_empty offenders,
      "The disable path is gone — ANYCABLE_ENABLED should not appear in: #{offenders}"
  end

  test "cable.yml uses the any_cable adapter in every app environment" do
    cable = YAML.load_file(ROOT.join("config/cable.yml"))

    %w[development performance production].each do |env|
      assert_equal "any_cable", cable[env]["adapter"], "#{env} must use the any_cable adapter"
    end
    assert_equal "test", cable["test"]["adapter"]
  end

  test "boot aborts loudly when ANYCABLE_ENABLED=false" do
    output = `RAILS_ENV=test ANYCABLE_ENABLED=false bin/rails runner "nil" 2>&1`

    refute $?.success?, "boot must abort when ANYCABLE_ENABLED=false, not silently degrade"
    assert_match(/ANYCABLE_ENABLED=false is no longer supported/, output)
  end

  # Push gating reads presence over anycable-go's HTTP API (Room::PresenceSet).
  # anycable-go serves that API only when it's protected one way or another, and
  # *disables* it otherwise — so the danger isn't an exposed endpoint, it's a
  # silently absent one: every presence read would degrade to "unavailable" and
  # push members who are sitting in the room reading. These pin the protection
  # the read path assumes.
  test "boot aborts when ANYCABLE_SECRET is blank in production" do
    output = `env -u ANYCABLE_SECRET RAILS_ENV=production APP_HOST=example.com SECRET_KEY_BASE=x bin/rails runner "nil" 2>&1`

    refute $?.success?, "a blank ANYCABLE_SECRET must abort, not degrade presence to unavailable"
    assert_match(/Missing required environment variables:.*ANYCABLE_SECRET/, output)
  end

  test "every shipped launch point protects the presence API with a secret" do
    deploy_accessory_envs.each do |file, env|
      assert_includes Array(env["secret"]), "ANYCABLE_SECRET",
        "#{file} must pass a secret, or anycable-go disables the presence API"
    end

    assert_match(/--secret=/, procfile_anycable_command,
      "Procfile.dev must pass a secret, or anycable-go disables the presence API"
    )
  end

  test "no shipped launch point opens a dedicated API port or public mode" do
    deploy_accessory_envs.each do |file, env|
      %w[ANYCABLE_API_PORT ANYCABLE_PUBLIC].each do |key|
        assert_nil env["clear"][key], "#{file} must not set #{key} — it would serve the API unauthenticated"
      end
    end

    %w[--api_port --public].each do |flag|
      refute_match(/#{Regexp.escape(flag)}/, procfile_anycable_command,
        "Procfile.dev must not pass #{flag} — it would serve the API unauthenticated"
      )
    end
  end

  # KTD7: presence TTL is how long push stays suppressed after a socket dies
  # silently. It has to clear the client's worst-case reconnect (~34s) or a blip
  # pushes someone who never left. The 15s default does not.
  test "presence TTL is set explicitly and clears the worst-case reconnect" do
    ttls = deploy_accessory_envs.to_h { |file, env| [ file, env["clear"]["ANYCABLE_PRESENCE_TTL"] ] }
    ttls["Procfile.dev"] = procfile_anycable_command[/--presence_ttl=(\S+)/, 1]

    ttls.each do |file, ttl|
      refute_nil ttl, "#{file} must set presence TTL explicitly — the 15s default is under the reconnect window"
      # Bare seconds. anycable-go takes an int here and dies on startup with a
      # parse error given a duration string, so "45s" would break every boot.
      assert_match(/\A\d+\z/, ttl, "#{file} presence TTL (#{ttl}) must be bare seconds — anycable-go rejects '45s'")
      assert_operator ttl.to_i, :>=, 45, "#{file} presence TTL (#{ttl}) must clear the ~34s worst-case reconnect"
    end

    assert_equal 1, ttls.values.uniq.size, "presence TTL must not drift between launch points: #{ttls}"
  end

  private
    def deploy_accessory_envs
      %w[config/deploy.yml config/deploy.multitenant.yml].to_h do |file|
        config = YAML.load_file(ROOT.join(file), aliases: true)
        [ file, config.dig("accessories", "anycable", "env") ]
      end
    end

    def procfile_anycable_command
      File.read(ROOT.join("Procfile.dev"))[/^anycable:.*$/]
    end
end
