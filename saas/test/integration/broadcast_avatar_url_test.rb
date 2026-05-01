# frozen_string_literal: true

require_relative "../test_helper"

class BroadcastAvatarUrlTest < ActiveSupport::TestCase
  # Regression: when a Turbo Stream broadcast renders a message body that
  # contains a mention attachment, the avatar URL inside the rendered partial
  # must include the workspace prefix.
  #
  # Without TenantedRendering wrapping the render with
  # ActionText::Content.with_renderer, ActionText falls back to its own
  # anonymous renderer with no script_name and emits prefix-less avatar URLs.
  # Those URLs then get baked into broadcast HTML and the fragment cache,
  # which 404s for everyone.
  test "broadcast render of a mention includes workspace prefix in avatar URL" do
    identity = GlobalIdentity.create!(
      name: "Mention Tester",
      email_address: "mention@example.com",
      verified_at: Time.current
    )

    with_provisioned_workspace(name: "Mention WS", creator: identity) do |workspace|
      ApplicationRecord.with_tenant(workspace.external_id.to_s) do
        bot = User.create_bot!(name: "MentionBot", bot_token: "abc123")

        body_html = %(<action-text-attachment sgid="#{bot.attachable_sgid}" content-type="application/vnd.sabha.mention" content=""></action-text-attachment>)
        content = ActionText::Content.new(body_html)

        rendered = Sabha::Saas::TenantedRendering.render(
          workspace.slug,
          :html,
          inline: "<%= content %>",
          locals: { content: content }
        )

        avatar_src = rendered[/src="([^"]*avatar[^"]*)"/, 1]
        assert avatar_src.present?, "Expected an avatar img in rendered output"
        assert avatar_src.start_with?("#{workspace.slug}/users/"),
          "Avatar src missing workspace prefix #{workspace.slug.inspect}: #{avatar_src.inspect}"
      end
    end
  ensure
    identity&.destroy
  end
end
