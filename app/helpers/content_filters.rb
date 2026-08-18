module ContentFilters
  # Formatting the rich text editor produces that Rails' sanitizers don't allow
  # by default. Declared once here and shared by every sanitization layer a
  # message passes through on its way to the screen:
  #
  #   * SanitizeTags strips disallowed markup from the stored body
  #   * Action Text sanitizes the rendered content (lib/rails_ext/action_text_allowed_tags.rb)
  #
  # `s`/`u`/`mark` come from the toolbar and markdown; the table tags let pasted
  # and markdown tables survive rather than being silently stripped.
  EDITOR_FORMATTING_TAGS = %w[ s u mark table thead tbody tfoot tr td th ]
  EDITOR_FORMATTING_ATTRIBUTES = %w[ data-language colspan rowspan ]

  def self.text_message_presentation_filters
    @text_message_presentation_filters ||= ActionText::Content::Filters.new(RemoveSoloUnfurledLinkText, SanitizeTags)
  end
end
