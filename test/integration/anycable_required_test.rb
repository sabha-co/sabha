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
end
