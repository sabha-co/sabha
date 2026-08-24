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

  # Waits for the suggestion to appear, then commits the selected one with Tab.
  #
  # The prompt filters server-side, so the menu opens on the unfiltered list and
  # swaps it when the request lands. Nodes caught mid-swap read as "<<ERROR>>",
  # and the first request of a run is slow enough to outlast the default wait —
  # hence a round-trip's worth of patience rather than the page default.
  def pick_mention(name)
    assert_selector ".lexxy-prompt-menu__item", text: name, wait: 15
    composer_editor.send_keys :tab
  end

  def assert_composer_text(text)
    assert_selector "#composer lexxy-editor .lexxy-editor__content", text: text
  end

  def assert_composer_empty
    assert_no_selector "#composer lexxy-editor .lexxy-editor__content", text: /./
  end

  # Simulates pasting plain text so tests can exercise the paste-driven flows (e.g.
  # a bare URL that unfurls into an embed).
  def paste_in_composer(text)
    paste_into composer_editor, text
  end

  # The edit form renders its own lexxy-editor, so pasting while editing must target
  # that instance rather than the main composer.
  def paste_in_edit_editor(text)
    paste_into find(".message__body-content--editing lexxy-editor .lexxy-editor__content"), text
  end

  def assert_edit_editor_text(text)
    assert_selector ".message__body-content--editing lexxy-editor", text: text
  end

  private
    def paste_into(content, text)
      content.click

      page.execute_script(<<~JS, content, text)
        const content = arguments[0]
        const event = new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: new DataTransfer() })
        event.clipboardData.setData("text/plain", arguments[1])
        content.dispatchEvent(event)
      JS
    end
end
