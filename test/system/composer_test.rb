require "application_system_test_case"

class ComposerTest < ApplicationSystemTestCase
  setup do
    sign_in "david@37signals.com"
    join_room rooms(:hq)
  end

  test "enter sends the message; shift+enter is a newline" do
    type_in_composer "A quick reply"
    press_in_composer :enter

    assert_message_text "A quick reply"
    assert_composer_empty

    # The persistent format bar no longer flips Enter to a newline — Shift is the
    # newline, plain Enter still sends.
    type_in_composer "line one"
    press_in_composer :shift, :enter
    type_in_composer "line two"

    assert_composer_text "line one"
    assert_no_selector ".message__body", text: "line one"
  end

  test "the format bar's @ button opens the mention prompt" do
    find("#composer .composer__mention-btn").click
    # The button drops the "@"; typing narrows the open prompt like normal.
    press_in_composer "Jas"
    pick_mention "Jason"
    click_on "send"

    assert_selector last_message_selector(".mention"), text: "Jason"
    assert_equal [ users(:jason) ], rooms(:hq).messages.ordered.last.mentionees
  end

  test "the emoji button inserts an emoji into the composer" do
    find("#composer .composer__emoji-btn").click

    within "#composer .composer__emoji-dialog" do
      find(".reaction-grid__btn[title='Fire']").click
    end

    assert_composer_text "🔥"
    click_on "send"
    assert_message_text "🔥"
  end

  test "mentioning a user with @ inserts a mention that persists" do
    type_in_composer "Hey @Dav"
    pick_mention "David"
    click_on "send"

    assert_selector ".message:last-of-type .message__body .mention", text: "David"

    message = rooms(:hq).messages.ordered.last
    assert_includes message.body.body.to_html, "application/vnd.sabha.mention"
    assert_equal [ users(:david) ], message.mentionees
  end

  test "clicking a mention opens its profile popup" do
    type_in_composer "Hey @Jas"
    pick_mention "Jason"
    click_on "send"

    within last_message_selector(".mention") do
      assert_selector ".mention__summary[aria-expanded='false']"
      find(".mention__summary").click

      assert_selector ".message__avatar-menu", visible: true
      assert_selector ".mention__summary[aria-expanded='true']"
    end
    assert_selector "#{last_message_selector(".mention")}[data-open]"
  end

  test "editing a message with a mention keeps the mention" do
    type_in_composer "Hey @Jas"
    pick_mention "Jason"
    click_on "send"

    assert_selector last_message_selector(".mention"), text: "Jason"
    message = rooms(:hq).messages.ordered.last

    within_message message do
      reveal_message_actions
      click_on "Edit"
      assert_edit_editor_text "Jason"
      click_on "Save changes"
    end

    assert_selector last_message_selector(".mention"), text: "Jason"
    assert_equal [ users(:jason) ], message.reload.mentionees
  end

  # A message authored in the Trix era stores its mention and opengraph embed as
  # node attributes; editing it under Lexxy must round-trip both intact.
  test "editing a legacy trix message keeps its mention and embed" do
    body = %(<div>Hey #{mention_attachment_for(:jason)} check <action-text-attachment content-type="application/vnd.actiontext.opengraph-embed" url="https://example.com/image.png" href="https://example.com/" filename="Example title" caption="Example description"></action-text-attachment></div>)
    message = Message.create! room: rooms(:hq), body: body, client_message_id: "legacy", creator: users(:david)

    join_room rooms(:hq)

    within_message message do
      reveal_message_actions
      click_on "Edit"
      assert_edit_editor_text "Jason"
      click_on "Save changes"
    end

    assert_selector last_message_selector(".mention"), text: "Jason"
    assert_selector last_message_selector(%(.og-embed__title a[href="https://example.com/"])), text: "Example title"
    assert_equal [ users(:jason) ], message.reload.mentionees
  end

  test "pasting a URL unfurls an opengraph preview" do
    stub_unfurl "Example Site", "https://example.com/article"

    paste_in_composer "https://example.com/article"

    within "#composer" do
      assert_selector ".og-embed__title", text: "Example Site", wait: 10
    end

    click_on "send"

    assert_selector last_message_selector(".og-embed__title"), text: "Example Site"
  end

  test "pasting a URL while editing unfurls a preview that persists" do
    message = Message.create! room: rooms(:hq), body: "Original", client_message_id: "edit-unfurl", creator: users(:david)
    join_room rooms(:hq)

    stub_unfurl "Example Site", "https://example.com/article"

    within_message message do
      reveal_message_actions
      click_on "Edit"
      assert_selector ".message__body-content--editing lexxy-editor"
    end

    paste_in_edit_editor "https://example.com/article"
    assert_selector ".message__body-content--editing .og-embed__title", text: "Example Site", wait: 10
    click_on "Save changes"

    assert_selector last_message_selector(".og-embed__title"), text: "Example Site"
  end

  private
    def last_message_selector(inner)
      ".message:last-of-type .message__body #{inner}"
    end

    def stub_unfurl(title, url, description: "An example article")
      metadata = Opengraph::Metadata.new(title:, url:, description:, image: "")
      Opengraph::Metadata.stubs(:from_url).returns(metadata)
    end
end
