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
    def compose_everyone
      assert_selector "trix-editor"
      # A mention is a Trix *attachment* (contentType application/vnd.sabha.mention),
      # not raw HTML — Trix's sanitizer strips the class off an inserted <span>, so
      # insertHTML never produces a detectable .mention--everyone. Insert the real
      # attachment with a valid signed GlobalID so both the composer's confirm gate
      # and the sent message resolve @everyone, matching mentions_autocomplete_handler.js.
      sgid = Everyone.new.attachable_sgid
      page.execute_script(<<~JS)
        const editor = document.querySelector("trix-editor").editor
        const attachment = new Trix.Attachment({
          content: '<span class="mention mention--everyone" sgid="#{sgid}">@everyone</span>',
          contentType: "application/vnd.sabha.mention",
          sgid: "#{sgid}"
        })
        editor.insertAttachment(attachment)
        editor.insertString(" ")
      JS
    end
end
