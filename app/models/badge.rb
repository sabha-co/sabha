class Badge < ApplicationRecord
  # A fixed, contrast-checked palette — badges pick a hue, not a free colour.
  # Every hue reads on the 14% fill it generates for the chip.
  COLORS = %w[ #8257E0 #4F52D9 #1B8F53 #B4730C #C7443F #12A594 #E0407A #2F6FEB ].freeze
  DEFAULT_COLOR = "#8257E0"

  has_many :users, dependent: :nullify

  attribute :color, default: DEFAULT_COLOR

  normalizes :name, with: ->(name) { name.strip.upcase }

  validates :name, presence: true, length: { maximum: 10 }, uniqueness: { case_sensitive: false }
  validates :color, inclusion: { in: COLORS }

  scope :ordered, -> { order(:id) }

  # Snap an arbitrary hex to the nearest palette hue by RGB distance. Blanks and
  # unparseable values fall back to the default so a badge always has a hue.
  def self.nearest_palette_color(value)
    return DEFAULT_COLOR if value.blank?

    normalized = value.to_s.upcase
    return normalized if COLORS.include?(normalized)

    target = rgb(normalized) or return DEFAULT_COLOR
    COLORS.min_by { |hue| rgb(hue).zip(target).sum { |a, b| (a - b)**2 } }
  end

  def self.rgb(hex)
    match = hex.match(/\A#([0-9A-F]{6})\z/) or return nil
    match[1].scan(/../).map { |pair| pair.to_i(16) }
  end
  private_class_method :rgb
end
