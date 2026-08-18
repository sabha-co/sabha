# Drives the Lexxy rich text editor in system tests. Encapsulates the editor's
# selectors and interactions so tests describe behavior, not the editor's DOM.
# Overrides Capybara's built-in fill_in_rich_text_area (which drives Trix) so the
# shared send_message helper keeps working.
module RichTextEditorHelper
  def fill_in_rich_text_area(id, with:)
    find("lexxy-editor##{id}", visible: :all)
    page.execute_script("document.getElementById(arguments[0]).value = arguments[1]", id, with)
  end

  def composer_editor
    find("#composer lexxy-editor .lexxy-editor__content")
  end

  def type_in_composer(text)
    composer_editor.click
    composer_editor.send_keys(text)
  end

  def press_in_composer(*keys)
    composer_editor.send_keys(*keys)
  end

  # The rich text button is only displayed for fine-pointer devices, a media
  # query headless Chrome doesn't satisfy, so click it directly.
  def toggle_rich_text_toolbar
    page.execute_script("document.querySelector('#composer .composer__rich-text-btn').click()")
  end

  # Waits for the suggestion to appear, then commits the selected one with Tab.
  def pick_mention(name)
    assert_selector ".lexxy-prompt-menu__item", text: name
    composer_editor.send_keys :tab
  end

  def assert_composer_text(text)
    assert_selector "#composer lexxy-editor .lexxy-editor__content", text: text
  end

  def assert_composer_empty
    assert_no_selector "#composer lexxy-editor .lexxy-editor__content", text: /./
  end

  # Simulates pasting plain text into the composer so tests can exercise the
  # paste-driven flows (e.g. a bare URL that unfurls into an embed).
  def paste_in_composer(text)
    composer_editor.click

    page.execute_script(<<~JS, text)
      const content = document.querySelector("#composer lexxy-editor .lexxy-editor__content")
      const event = new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: new DataTransfer() })
      event.clipboardData.setData("text/plain", arguments[0])
      content.dispatchEvent(event)
    JS
  end

  def assert_edit_editor_text(text)
    assert_selector ".message__body-content--editing lexxy-editor", text: text
  end
end
