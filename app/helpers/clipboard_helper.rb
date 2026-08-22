module ClipboardHelper
  # Copy-to-clipboard button. Pass `toast:` to raise a confirmation toast on
  # copy (in addition to the button's success flash) — useful for text buttons
  # where the flash alone is easy to miss.
  def button_to_copy_to_clipboard(url, btn_class: "btn", toast: nil, &block)
    tag.button class: btn_class, data: {
      controller: "copy-to-clipboard", action: "copy-to-clipboard#copy",
      copy_to_clipboard_success_class: "btn--success", copy_to_clipboard_content_value: url
    } do
      safe_join([ capture(&block), copy_toast_template(toast) ].compact)
    end
  end

  private
    def copy_toast_template(message)
      return unless message

      tag.template(data: { copy_to_clipboard_target: "toast" }) do
        render "shared/toast", message: message
      end
    end
end
