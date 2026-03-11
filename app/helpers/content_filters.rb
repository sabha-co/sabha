module ContentFilters
  def self.text_message_presentation_filters
    @text_message_presentation_filters ||= ActionText::Content::Filters.new(RemoveSoloUnfurledLinkText, StyleUnfurledTwitterAvatars, SanitizeTags)
  end
end
