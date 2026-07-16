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

  test "every launch point protects the presence API with a secret" do
    launch_points.each do |file, settings|
      assert settings["ANYCABLE_SECRET"].present?,
        "#{file} must pass a secret, or anycable-go disables the presence API"
    end
  end

  test "no launch point opens a dedicated API port or public mode" do
    launch_points.each do |file, settings|
      %w[ANYCABLE_API_PORT ANYCABLE_PUBLIC].each do |key|
        assert_nil settings[key], "#{file} must not set #{key} — it would serve the API unauthenticated"
      end
    end
  end

  # Presence lives in the broker component. Drop it and the presence API reports
  # unsupported, every read degrades to the connected_at fallback, and push goes
  # to people who are sitting in the room reading — silently, since nothing raises.
  test "every launch point runs a broker, which presence requires" do
    launch_points.each do |file, settings|
      assert_equal "memory", settings["ANYCABLE_BROKER"],
        "#{file} must run the memory broker, or the presence API reports unsupported and push fails open"
    end
  end

  # Presence TTL is how long push stays suppressed after a socket dies silently.
  # It has to clear the client's worst-case reconnect (~34s) or a blip pushes
  # someone who never left. The 15s default does not.
  test "presence TTL is set explicitly and clears the worst-case reconnect" do
    ttls = launch_points.transform_values { |settings| settings["ANYCABLE_PRESENCE_TTL"] }

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
    # Every place we start anycable-go, normalized to the ANYCABLE_* settings it
    # ends up running with, whatever syntax the file uses. The load harness is in
    # here deliberately: if it drifts from production it measures the wrong path
    # while looking like it measured the right one.
    def launch_points
      {
        "config/deploy.yml" => deploy_settings("config/deploy.yml"),
        "config/deploy.multitenant.yml" => deploy_settings("config/deploy.multitenant.yml"),
        "Procfile.dev" => procfile_settings,
        "bin/load-anycable" => load_harness_settings
      }
    end

    def deploy_settings(file)
      env = YAML.load_file(ROOT.join(file), aliases: true).dig("accessories", "anycable", "env")
      secrets = Array(env["secret"]).to_h { |key| [ key, "(from secrets)" ] }

      env["clear"].merge(secrets)
    end

    # `anycable: anycable-go --broker=memory --presence_ttl=45 …`
    def procfile_settings
      command = File.read(ROOT.join("Procfile.dev"))[/^anycable:.*$/]

      command.scan(/--(\w+)=(\S+)/).to_h { |flag, value| [ "ANYCABLE_#{flag.upcase}", value ] }
    end

    # `execute :docker, :run, … "-e", "ANYCABLE_BROKER=memory", …`, scoped to the
    # anycable container so the web container's env doesn't answer for it.
    def load_harness_settings
      block = File.read(ROOT.join("bin/load-anycable"))[/:sabha_anycable.*?anycable\/anycable-go/m]

      block.scan(/"(ANYCABLE_\w+)=([^"]*)"/).to_h
    end
end
