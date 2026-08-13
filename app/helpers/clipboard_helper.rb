module ClipboardHelper
  def button_to_copy_to_clipboard(url, btn_class: "btn", &)
    tag.button class: btn_class, data: {
      controller: "copy-to-clipboard", action: "copy-to-clipboard#copy",
      copy_to_clipboard_success_class: "btn--success", copy_to_clipboard_content_value: url
    }, &
  end
end
