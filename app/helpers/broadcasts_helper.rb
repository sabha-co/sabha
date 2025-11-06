module BroadcastsHelper
  def broadcast_image_tag(image, options)
    image_tag(broadcast_image_path(image), options)
  end

  def broadcast_image_path(image)
    if image.is_a?(Symbol) || image.is_a?(String)
      image_path(image)
    else
      polymorphic_url(image, only_path: true)
    end
  end
end
