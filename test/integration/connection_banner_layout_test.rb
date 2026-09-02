require "test_helper"

class ConnectionBannerLayoutTest < ActiveSupport::TestCase
  test "every shell banner has a named row above the header" do
    css = File.read(Rails.root.join("app/assets/stylesheets/application/layout.css"))
    templates = css.scan(/grid-template-areas:\s*(.*?);/m).flatten

    assert_predicate templates, :any?
    templates.each do |template|
      assert_includes template, "notice",
        "every shell grid must reserve the shared notice banner instead of auto-placing it below the header"
      assert_includes template, "connection",
        "every shell grid must reserve the reconnect banner instead of auto-placing it below the header"
    end

    assert_match(/\.top-banner\s*\{.*?grid-area:\s*notice;/m, css)
    assert_match(/\.connection-banner\s*\{.*?grid-area:\s*connection;/m, css)
  end
end
