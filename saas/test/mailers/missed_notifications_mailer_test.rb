# frozen_string_literal: true

require_relative "../test_helper"

# Path-based SaaS routing puts workspace ids in the URL: /1000001/inbox/activity.
# Mailer URL helpers must include `script_name: tenant_script_name` or links land
# at the global tenant resolver and 404. Unsubscribe is the only exception — the
# token carries tenant, and the route is intentionally global so any inbox client
# can hit it.
class MissedNotificationsMailerTest < ActionMailer::TestCase
  test "Activity and settings links carry workspace prefix; unsubscribe stays global" do
    with_provisioned_workspace(name: "Mailer Test", creator: global_identities(:alice)) do |workspace|
      tenant_id = workspace.external_id.to_s

      ApplicationRecord.with_tenant(tenant_id) do
        recipient = User.administrator.first
        actor = User.create!(
          name: "Sender",
          email_address: "sender-#{SecureRandom.hex(4)}@example.com",
          password_digest: BCrypt::Password.create("secret123456"),
          verified_at: 1.day.ago,
          status: :active
        )
        room = Rooms::Open.first

        message = room.messages.create!(
          body: "<div>hello</div>",
          creator: actor,
          client_message_id: "saas_missed_#{SecureRandom.hex(4)}"
        )
        bundle = Notification::Bundle.create!(
          user: recipient, frequency: :hourly,
          starts_at: Time.current, ends_at: 1.hour.from_now
        )
        item = Notification::BundleItem.create!(
          bundle: bundle, message: message, actor: actor, kind: "mention"
        )

        mail = MissedNotificationsMailer.bundle(bundle, [ item ])

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
