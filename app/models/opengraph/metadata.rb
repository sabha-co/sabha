class Opengraph::Metadata
  include ActiveModel::Model
  include ActiveModel::Validations::Callbacks
  include ActionView::Helpers::SanitizeHelper

  include Fetching

  ATTRIBUTES = %i[ title url image description ]
  attr_accessor *ATTRIBUTES

  before_validation :sanitize_fields

  validates_presence_of :title, :url, :description
  validate :ensure_valid_image_url

  private
    def sanitize_fields
      self.title = strip_tags(remove_script_tags(title))
      self.description = strip_tags(remove_script_tags(description))
    end

    def remove_script_tags(text)
      return text if text.blank?
      # Remove script tags and their content
      text.gsub(/<script[^>]*>.*?<\/script>/mi, "")
    end

    def ensure_valid_image_url
      if image.present?
        errors.add :image, "url is invalid" unless Opengraph::Location.new(image).valid?
      end
    end
end
