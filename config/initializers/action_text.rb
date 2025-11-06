Rails.application.config.after_initialize do
  # Allow inline SVG images when rendering rich text content
  _original_verbose, $VERBOSE = $VERBOSE, nil
  Loofah::HTML5::SafeList::PROTOCOL_SEPARATOR = /:|,|;|(&#0*58)|(&#x70)|(&#x0*3a)|(%|&#37;)3A/i
  $VERBOSE = _original_verbose
  Loofah::HTML5::SafeList::ALLOWED_URI_DATA_MEDIATYPES << "image/svg+xml"

  # Support inline user popups for mentions inside ActionText
  Rails::HTML4::SafeListSanitizer.allowed_tags += %w[details summary section turbo-frame]
  Rails::HTML4::SafeListSanitizer.allowed_attributes += %w[id data-controller data-action data-popup-orientation-top-class data-popup-target style]
end
