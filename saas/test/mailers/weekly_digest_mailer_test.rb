# frozen_string_literal: true

require_relative "../test_helper"

# See missed_notifications_mailer_test.rb header — same path-routing rule for
# digest links; same global exemption for unsubscribe.
class WeeklyDigestMailerTest < ActionMailer::TestCase
  test "Activity and settings links carry workspace prefix; unsubscribe stays global" do
    with_provisioned_workspace(name: "Digest Mailer Test", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s

      ApplicationRecord.with_tenant(tenant_id) do
        user = User.administrator.first
        actor = User.create!(
          name: "Author",
          email_address: "author-#{SecureRandom.hex(4)}@example.com",
          password_digest: BCrypt::Password.create("secret123456"),
          verified_at: 1.day.ago,
          status: :active
        )
        room = Rooms::Open.first

        everyone_message = room.messages.create!(
          body: "<div>weekly heads up</div>",
          creator: actor,
          client_message_id: "saas_digest_#{SecureRandom.hex(4)}",
          mentions_everyone: true
        )

        content = Struct.new(:everyone_mentions, :active_rooms, :excerpts).new(
          [ everyone_message ],
          [ [ room, 5 ] ],
          [ everyone_message ]
        )

        mail = WeeklyDigestMailer.digest(user, content)

        body = mail.html_part.body.to_s
        assert_includes body, "/#{tenant_id}/inbox/activity",
          "Activity CTA must include workspace prefix #{tenant_id}"
        assert_includes body, "/#{tenant_id}/users/me/notification_settings/edit",
          "Settings link must include workspace prefix #{tenant_id}"

        unsubscribe_in_body = body[/(https?:\/\/[^"'\s]*email\/unsubscribe\/[^"'\s]+)/, 1]
        refute_nil unsubscribe_in_body, "Body must contain an unsubscribe link"
        refute_includes unsubscribe_in_body, "/#{tenant_id}/",
          "Unsubscribe URL must remain global — token carries the tenant"

        list_unsub = mail.header["List-Unsubscribe"]&.value
        refute_includes list_unsub.to_s, "/#{tenant_id}/",
          "List-Unsubscribe header URL must remain global"
      end
    end
  end
end
