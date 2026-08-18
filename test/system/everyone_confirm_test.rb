require "application_system_test_case"

# U8: the composer asks a permitted sender to confirm @everyone once the room is
# above the configured threshold, showing the real recipient count. Below it,
# @everyone sends with no friction.
class EveryoneConfirmTest < ApplicationSystemTestCase
  setup do
    @original_threshold = Rails.configuration.x.everyone_mention.confirm_threshold
  end

  teardown do
    Rails.configuration.x.everyone_mention.confirm_threshold = @original_threshold
  end

  test "@everyone above the threshold asks for confirmation and sends once acknowledged" do
    Rails.configuration.x.everyone_mention.confirm_threshold = 1 # pets has 2 members
    sign_in "jason@37signals.com" # administrator
    join_room rooms(:pets)

    compose_everyone
    click_on "send"

    assert_text "Notify all 2 people in this room?"
    assert_message_text "@everyone", count: 0 # held until acknowledged

    click_on "Send to everyone"
    assert_message_text "@everyone"
  end

  test "@everyone below the threshold sends without a prompt" do
    Rails.configuration.x.everyone_mention.confirm_threshold = 1000
    sign_in "jason@37signals.com"
    join_room rooms(:pets)

    compose_everyone
    click_on "send"

    assert_no_text "Notify all"
    assert_message_text "@everyone"
  end

  private
    # Inject an @everyone mention straight into the editor (this test exercises the
    # confirm gate, not the mention prompt). The attachment renders the
    # everyone/mention partial as its editor content, so `.mention--everyone` — what
    # the composer keys off — lands in the DOM, and it persists as a real mention.
    def compose_everyone
      assert_selector "#composer lexxy-editor"

      everyone = Everyone.new
      content = ApplicationController.render(partial: "everyone/mention", locals: { everyone: everyone })
      attachment = %(<p><action-text-attachment sgid="#{everyone.attachable_sgid}" content-type="application/vnd.sabha.mention" content="#{CGI.escapeHTML(content)}"></action-text-attachment> </p>)

      fill_in_rich_text_area "message_body", with: attachment
      assert_selector "#composer .mention--everyone"
    end
end
