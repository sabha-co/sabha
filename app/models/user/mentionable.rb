module User::Mentionable
  include ActionText::Attachable

  # The editor namespaces mention attachments under "sabha" (see the Lexxy
  # initializer), and the composer only permits this content type.
  CONTENT_TYPE = "application/vnd.sabha.mention"

  def to_attachable_partial_path
    "users/mention"
  end

  # Rails' editor adapter regenerates the attachment node from the attachable when
  # it loads a stored mention back into the composer. Without this it defaults to
  # "application/octet-stream", which isn't permitted, so Lexxy drops the mention
  # on edit.
  def attachable_content_type
    CONTENT_TYPE
  end

  # Rails' editor adapter renders this when loading a stored mention back into the
  # composer (e.g. editing a message). It must be the simple inline chip, not the
  # interactive users/mention popup, which belongs on display only.
  def to_editor_content_attachment_partial_path
    "users/editor_mention"
  end

  def attachable_plain_text_representation(caption)
    "@#{name}"
  end
end
