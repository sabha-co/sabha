module QrCodeHelper
  def link_to_zoom_qr_code(url, &)
    id = Base64.urlsafe_encode64(url)

    link_to qr_code_path(id), class: "btn", data: {
      lightbox_target: "image", action: "lightbox#open", lightbox_url_value: qr_code_path(id) }, &
  end
end
