module RichTextHelper
  def rich_text_data_actions
    # submitByKeyboard runs in the capture phase so it can submit on Enter
    # before the editor turns the keystroke into a newline
    "lexxy:change->typing-notifications#start keydown->composer#submitByKeyboard:capture"
  end

  # The editor's native @-mention prompt. `src` filters server-side via `filter`,
  # so callers pass the room-scoped autocompletable path.
  def mention_prompt_tag(src)
    tag.lexxy_prompt trigger: "@", name: "mention", src: src,
      "remote-filtering": true, "empty-results": "No matches"
  end
end
