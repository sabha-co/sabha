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
      self.title = sanitize(strip_tags(title))
      self.description = sanitize(strip_tags(description))
    end

    def ensure_valid_image_url
      if image.present?
        errors.add :image, "url is invalid" unless Opengraph::Location.new(image).valid?
      end
    end
end
