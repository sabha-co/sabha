# Extend the rendering-time safelist for inline user popups (mentions). We
# override sanitizer_allowed_tags / _allowed_attributes (rather than setting
# ActionText::ContentHelper.allowed_tags directly) so ActionText's own
# additions — action-text-attachment, figure/figcaption, and
# ActionText::Attachment::ATTRIBUTES — keep flowing through.
module SabhaActionTextSafelist
  EXTRA_TAGS = %w[details summary section turbo-frame].freeze
  EXTRA_ATTRIBUTES = %w[id data-controller data-action data-popup-orientation-top-class data-popup-target style].freeze

  def sanitizer_allowed_tags
    super + EXTRA_TAGS
  end

  def sanitizer_allowed_attributes
    super + EXTRA_ATTRIBUTES
  end
end

Rails.application.config.after_initialize do
  # Allow inline SVG images when rendering rich text content
  _original_verbose, $VERBOSE = $VERBOSE, nil
  Loofah::HTML5::SafeList::PROTOCOL_SEPARATOR = /:|,|;|(&#0*58)|(&#x70)|(&#x0*3a)|(%|&#37;)3A/i
  $VERBOSE = _original_verbose
  Loofah::HTML5::SafeList::ALLOWED_URI_DATA_MEDIATYPES << "image/svg+xml"

  ActionText::ContentHelper.prepend(SabhaActionTextSafelist)
end
