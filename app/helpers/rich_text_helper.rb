module RichTextHelper
  def rich_text_data_actions
    # submitByKeyboard runs in the capture phase so it can submit on Enter
    # before the editor turns the keystroke into a newline
    "lexxy:change->typing-notifications#start lexxy:change->composer#draftChanged keydown->composer#submitByKeyboard:capture"
  end

  # The editor's native @-mention prompt. `src` filters server-side via `filter`,
  # so callers pass the room-scoped autocompletable path.
  def mention_prompt_tag(src)
    tag.lexxy_prompt trigger: "@", name: "mention", src: src,
      "remote-filtering": true, "empty-results": "No matches"
  end

  # Trix-era opengraph embeds carry their details as node attributes, which the
  # editor doesn't round-trip. Rendering them into the content attribute lets the
  # editor preserve them like any embed it created itself.
  def editable_body(message)
    fragment = ActionText::Fragment.wrap(message.body.body_before_type_cast)

    transformed = fragment.replace(legacy_embed_selector) do |node|
      node.tap { |n| n["content"] = render_action_text_attachment(ActionText::Attachment.from_node(n)) }
    end

    ActionText::RichText.new(body: transformed.to_html)
  end

  private
    # Built lazily: ActionText::Attachment::OpengraphEmbed is defined in a
    # deferred rails_ext file, so referencing it at module load (before that
    # runs) would break eager-loaded boots.
    def legacy_embed_selector
      "action-text-attachment[content-type='#{ActionText::Attachment::OpengraphEmbed::OPENGRAPH_EMBED_CONTENT_TYPE}'][href]"
    end
end
