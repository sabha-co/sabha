module RichTextHelper
  def rich_text_data_actions
    default_actions =
      "trix-change->typing-notifications#start keydown->composer#submitByKeyboard"

    autocomplete_actions =
      "trix-focus->rich-autocomplete#focus trix-change->rich-autocomplete#search trix-blur->rich-autocomplete#blur"

    [ default_actions, autocomplete_actions ].join(" ")
  end
end
